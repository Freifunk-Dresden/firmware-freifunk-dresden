/*
 * Copyright (C) 2006 BATMAN contributors:
 * Axel Neumann
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of version 2 of the GNU General Public
 * License as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA
 *
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdarg.h>
#include <syslog.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <sys/un.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <paths.h>

#include "batman.h"
#include "os.h"
#include "originator.h"
#include "metrics.h"
#include "plugin.h"
#include "schedule.h"
#include "objlist.h"
#include "tunnel.h"

static char run_dir[MAX_PATH_SIZE] = DEF_RUN_DIR;

static int8_t debug_level = -1;
static int32_t dbg_mute_to;

#define DEF_LOOP_PERIOD 1000

static int32_t loop_mode;

int unix_sock = 0;

LIST_ENTRY ctrl_list;

LIST_ENTRY dbgl_clients[DBGL_MAX + 1];
static struct dbg_histogram dbgl_history[2][DBG_HIST_SIZE];

static uint8_t debug_system_active = NO;

static char *init_string = NULL;

static int32_t Testing = NO;
int32_t Load_config;

char *prog_name;

struct opt_type Patch_opt;

LIST_ENTRY opt_list;

int32_t Client_mode = NO; //this one must be initialized manually!

static int mapSyslogPrio(int8_t dbgt)
{
	switch(dbgt)
	{
		case DBGT_INFO: return LOG_INFO;
		case DBGT_WARN: return LOG_WARNING;
		case DBGT_ERR:  return LOG_ERR;
		default: return LOG_NOTICE;
	}
}

static void remove_dbgl_node(struct ctrl_node *cn)
{
	for (int i = DBGL_MIN; i <= DBGL_MAX; i++)
	{
		OLForEach(pEntry, LIST_ENTRY, dbgl_clients[i])
		{
			if (((struct dbgl_node *)pEntry)->cn == cn)
			{
				OLRemoveEntry(pEntry);
				debugFree(pEntry, 218);
				cn->dbgl = DBGL_UNUSED;
				break;
			}
		}
	}
}

static void add_dbgl_node(struct ctrl_node *cn, int8_t dbgl)
{
	if (!cn || dbgl < DBGL_MIN || dbgl > DBGL_MAX)
		return;

	struct dbgl_node *dn = debugMalloc(sizeof(struct dbgl_node), 218);

	dn->cn = cn;
	cn->dbgl = dbgl;
	OLInsertTailList(&dbgl_clients[dbgl], (PLIST_ENTRY)dn);

	if (dbgl == DBGL_SYS || dbgl == DBGL_CHANGES)
	{
		dbg(DBGL_CHANGES, DBGT_INFO, "resetting muted dbg history");
		memset(dbgl_history, 0, sizeof(dbgl_history));
	}
}

static int daemonize()
{
	int fd = 0;

	switch (fork())
	{
	case -1:
		return -1;

	case 0:
		break;

	default:
		exit(EXIT_SUCCESS);
	}

	if (setsid() == -1)
		return -1;

	/* Ensure we are no session leader */
	if (fork())
		exit(EXIT_SUCCESS);

	errno = 0;
	if (chdir("/") < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "could not chdir to /: %s", strerror(errno));
	}

	if ((fd = open(_PATH_DEVNULL, O_RDWR, 0)) != -1)
	{
		dup2(fd, STDIN_FILENO);
		dup2(fd, STDOUT_FILENO);
		dup2(fd, STDERR_FILENO);

		if (fd > 2)
			close(fd);
	}

	return 0;
}

static int update_pid_file(void)
{
	char tmp_path[MAX_PATH_SIZE + 20] = "";
	int tmp_fd = 0;

	My_pid = getpid();

	sprintf(tmp_path, "%s/pid", run_dir);

	if ((tmp_fd = open(tmp_path, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)) < 0)
	{ //check permissions of generated file

		dbgf(DBGL_SYS, DBGT_ERR, "could not open %s - %s", tmp_path, strerror(errno));
		return FAILURE;
	}

	dprintf(tmp_fd, "%d\n", My_pid);

	close(tmp_fd);
	return SUCCESS;
}

static void activate_debug_system(void)
{
	if (!debug_system_active)
	{
		/* daemonize */
		if (debug_level == -1)
		{
			if (daemonize() < 0)
			{
				dbg(DBGL_SYS, DBGT_ERR, "can't fork to background: %s", strerror(errno));
				cleanup_all(-500093);
			}

			// fork will result in a new pid
			if (update_pid_file() == FAILURE)
				cleanup_all(-500132);
		}
		else
		{
			struct ctrl_node *cn = create_ctrl_node(STDOUT_FILENO, NULL, NO /*admin rights not necessary*/);

			add_dbgl_node(cn, debug_level);
		}

		//dbg( DBGL_CHANGES, DBGT_INFO, "resetting muted dbg history" );
		memset(dbgl_history, 0, sizeof(dbgl_history));

		debug_system_active = YES;

		dbgf_all(0, DBGT_INFO, "activated level %d", debug_level);

		dbg(DBGL_CHANGES, DBGT_INFO, "BMX %s%s (compatibility version %d): %s",
				SOURCE_VERSION,
				strncmp(REVISION_VERSION, "0", 1) != 0 ? REVISION_VERSION : "",
				COMPAT_VERSION, init_string);
	}
}

struct ctrl_node *create_ctrl_node(int fd, void (*cn_fd_handler)(struct ctrl_node *), uint8_t authorized)
{
	struct ctrl_node *cn = debugMalloc(sizeof(struct ctrl_node), 201);
	memset(cn, 0, sizeof(struct ctrl_node));
	OLInsertTailList(&ctrl_list, &(cn->entry));

	cn->fd = fd;
	cn->cn_fd_handler = cn_fd_handler;
	cn->dbgl = DBGL_UNUSED;
	cn->authorized = authorized;

	return cn;
}

void close_ctrl_node(uint8_t cmd, struct ctrl_node *ctrl_node)
{
	OLForEach(cn, struct ctrl_node, ctrl_list)
	{

		if ((cmd == CTRL_CLOSE_ERROR || cmd == CTRL_CLOSE_SUCCESS || cmd == CTRL_CLOSE_DELAY) && cn == ctrl_node)
		{
			if (cn->fd > 0 && cn->fd != STDOUT_FILENO)
			{
				cn->closing_stamp = MAX(batman_time, 1);
				remove_dbgl_node(cn);

				//leaving this after remove_dbgl_node() prevents debugging via broken -d4 pipe
				dbgf_all(0, DBGT_INFO, "closed ctrl node fd %d with cmd %d", cn->fd, cmd);

				if (cmd == CTRL_CLOSE_SUCCESS)
					UNUSED_RETVAL(write(cn->fd, CONNECTION_END_STR, strlen(CONNECTION_END_STR)));

				if (cmd != CTRL_CLOSE_DELAY)
				{
					close(cn->fd);
					cn->fd = 0;
					change_selects();
				}
			}

			return;
		}

		if ((cmd == CTRL_CLOSE_STRAIGHT && cn == ctrl_node) ||
				(cmd == CTRL_PURGE_ALL) ||
				(cmd == CTRL_CLEANUP
				  && cn->closing_stamp /* cn->fd <= 0  && */
				  && batman_time > (cn->closing_stamp + CTRL_CLOSING_TIMEOUT))
			 )
		{
			if (cn->fd > 0 && cn->fd != STDOUT_FILENO)
			{
				remove_dbgl_node(cn);
				//leaving this after remove_dbgl_node() prevents debugging via broken -d4 pipe
				dbgf_all(0, DBGT_INFO, "closed ctrl node fd %d", cn->fd);

				close(cn->fd);
				cn->fd = 0;
				change_selects();
			}

			PLIST_ENTRY prev = OLGetPrev(cn);
			OLRemoveEntry(cn);
			debugFree(cn, 1201);
			cn = (struct ctrl_node *)prev;
		}
	}
}

void accept_ctrl_node(void)
{
	struct sockaddr addr;
	socklen_t addr_size = sizeof(struct sockaddr);
	int32_t unix_opts = 0;

	int fd = accept(unix_sock, (struct sockaddr *)&addr, &addr_size);

	if (fd < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't accept unix client: %s", strerror(errno));
		return;
	}

	/* make unix socket non blocking */
	unix_opts = fcntl(fd, F_GETFL, 0);
	fcntl(fd, F_SETFL, unix_opts | O_NONBLOCK);

	create_ctrl_node(fd, NULL, YES);

	change_selects();

	dbgf_all(0, DBGT_INFO, "got unix control connection");
}

void handle_ctrl_node(struct ctrl_node *cn)
{
	char buff[MAX_UNIX_MSG_SIZE + 1];

	if (cn->cn_fd_handler)
	{
		(cn->cn_fd_handler)(cn);
		return;
	}

	errno = 0;
	int input = read(cn->fd, buff, MAX_UNIX_MSG_SIZE);

	buff[input] = '\0';

	if (input > 0 && input < MAX_UNIX_MSG_SIZE)
	{
		dbgf_all(0, DBGT_INFO, "rcvd ctrl stream via fd %d, %d bytes, auth %d: %s",
						 cn->fd, input, cn->authorized, buff);

		if ((apply_stream_opts(buff, NULL, OPT_CHECK, NO /*no cfg by default*/, cn) == FAILURE) ||
				(apply_stream_opts(buff, NULL, OPT_APPLY, NO /*no cfg by default*/, cn) == FAILURE))
		{
			dbg(DBGL_SYS, DBGT_ERR, "invalid ctrl stream via fd %d, %d bytes, auth %d: %s",
					cn->fd, input, cn->authorized, buff);

			close_ctrl_node(CTRL_CLOSE_ERROR, cn);
			return;
		}

		respect_opt_order(OPT_APPLY, 0, 99, NULL, NO /*load_cofig*/, OPT_POST, 0 /*probably closed*/);
	}
	else
	{
		close_ctrl_node(CTRL_CLOSE_STRAIGHT, cn);
		//stephan: remove debug print on closed and already freed cn
		//bmxd crashed when bmxd -cd4
	}
}

// returns DBG_HIST_NEW, DBG_HIST_MUTING, or  DBG_HIST_MUTED
static uint8_t check_dbg_history(int8_t dbgl, char *s, uint32_t expire, uint16_t check_len)
{
	static int r = 0;
	int i = 0;
	int unused_i = 0;
	int h = 0;

	check_len = MIN(check_len, DBG_HIST_TEXT_SIZE);

	if (!strlen(s) || !expire || !check_len)
		return DBG_HIST_NEW;

	if (dbgl == DBGL_SYS)
		h = 0;

	else if (dbgl == DBGL_CHANGES)
		h = 1;

	else
		return DBG_HIST_NEW;

	unused_i = -1;
	i = r = (r + 1) % DBG_HIST_SIZE;

	do
	{
		if (dbgl_history[h][i].check_len == check_len &&
				dbgl_history[h][i].expire == expire &&
				!memcmp(s, dbgl_history[h][i].text, MIN(check_len, strlen(s))))
		{
			if (    batman_time < (dbgl_history[h][i].print_stamp + expire)
			    &&	batman_time >= dbgl_history[h][i].print_stamp)
			{
				dbgl_history[h][i].catched++;

				if (dbgl_history[h][i].catched == 2)
					return DBG_HIST_MUTING;

				return DBG_HIST_MUTED;
			}

			dbgl_history[h][i].print_stamp = batman_time;
			dbgl_history[h][i].catched = 1;
			return DBG_HIST_NEW;
		}

		if (   unused_i == -1
		    && (     dbgl_history[h][i].catched == 0
				     || !( batman_time < (dbgl_history[h][i].print_stamp + expire) &&
					         batman_time >= dbgl_history[h][i].print_stamp)
				)
			 )
		{
			unused_i = i;
		}

		i = ((i + 1) % DBG_HIST_SIZE);

	} while (i != r);

	if (unused_i == -1)
		unused_i = r;

	dbgl_history[h][unused_i].expire = expire;
	dbgl_history[h][unused_i].check_len = check_len;
	dbgl_history[h][unused_i].print_stamp = batman_time;
	dbgl_history[h][unused_i].catched = 1;
	memcpy(dbgl_history[h][unused_i].text, s, MIN(check_len, strlen(s)));

	return DBG_HIST_NEW;
}

#define MAX_DBG_WRITES 4
void dbg_printf(struct ctrl_node *cn, char *last, ...)
{
	if (!cn || cn->fd <= 0)
		return;

	static char s[MAX_DBG_STR_SIZE + 1];
	ssize_t w = 0;
	ssize_t out = 0;
	int i = 1;

	va_list ap;
	va_start(ap, last);
	vsnprintf(s, MAX_DBG_STR_SIZE, last, ap);
	va_end(ap);

	// CONNECTION_END_CHR is reserved for signaling connection end
	paranoia(-500146, (strchr(s, CONNECTION_END_CHR)));

	errno = 0;

	while ((w = write(cn->fd, s + out, strlen(s + out))) != (ssize_t)strlen(s + out))
	{
		if (errno == EPIPE || i >= MAX_DBG_WRITES || cn->dbgl == DBGL_ALL)
		{
			if (cn->dbgl != DBGL_ALL)
			{
				syslog(mapSyslogPrio(DBGT_ERR), "failed %d times writing %d instead of %d/%d bytes (%s)! Giving up: %s\n",
							 i, (int)w, (int)strlen(s + out), (int)strlen(s), strerror(errno), s + out);
			}

			break;
		}
		i++;

		bat_wait(0, 10);

		if (w > 0)
			out += w;

		errno = 0;
	}
}

static void debug_output(uint8_t indent, uint32_t check_len, uint32_t expire, struct ctrl_node *cn, int8_t dbgl, int8_t dbgt, char const *f, char *s)
{
	static uint16_t dbgl_all_msg_num = 0;
	static char *dbgt2str[] = {"", "INFO  ", "WARN  ", "ERROR "};

	int16_t dbgl_out[DBGL_MAX + 1];
	int i = 0;
	int j = 0;

	uint8_t mute_dbgl_sys = DBG_HIST_NEW;
	uint8_t mute_dbgl_changes = DBG_HIST_NEW;

	char format[32] = ""; //max 16: "%s%256s%s%s%s\n"
	char *space = "---------";
	snprintf(format,sizeof(format),"%%s%%.%ds%%s%%s%%s\n", indent);

	if (cn && cn->fd != STDOUT_FILENO)
	{
		dbg_printf(cn, format, dbgt2str[dbgt], space, f ? f : "", f ? "(): " : "", s);
	}

	if (!debug_system_active)
	{
		if (dbgl == DBGL_SYS || debug_level == DBGL_ALL || debug_level == dbgl)
		{
			//printf("[%d %8llu] %s%s%s%s\n", My_pid, (unsigned long long)batman_time, dbgt2str[dbgt], f ? f : "", f ? "(): " : "", s);
			printf(format, dbgt2str[dbgt], space, f ? f : "", f ? "(): " : "", s);
		}
		if (dbgl == DBGL_SYS)
		{
			syslog(mapSyslogPrio(dbgt), format, dbgt2str[dbgt], space, f ? f : "", f ? "(): " : "", s);
		}

		return;
	}

	if (dbgl == DBGL_ALL)
	{
		if (!OLIsListEmpty(&dbgl_clients[DBGL_ALL]))
			dbgl_out[i++] = DBGL_ALL;
	}
	else if (dbgl == DBGL_CHANGES)
	{
		if (!OLIsListEmpty(&dbgl_clients[DBGL_CHANGES]))
			dbgl_out[i++] = DBGL_CHANGES;
		if (!OLIsListEmpty(&dbgl_clients[DBGL_ALL]))
			dbgl_out[i++] = DBGL_ALL;
	}
	else if (dbgl == DBGL_TEST)
	{
		if (!OLIsListEmpty(&dbgl_clients[DBGL_TEST]))
			dbgl_out[i++] = DBGL_TEST;
		if (!OLIsListEmpty(&dbgl_clients[DBGL_ALL]))
			dbgl_out[i++] = DBGL_ALL;
	}
	else if (dbgl == DBGL_PROFILE)
	{
		if (!OLIsListEmpty(&dbgl_clients[DBGL_PROFILE]))
			dbgl_out[i++] = DBGL_PROFILE;
	}
	else if (dbgl == DBGL_SYS)
	{
		if (!OLIsListEmpty(&dbgl_clients[DBGL_SYS]))
			dbgl_out[i++] = DBGL_SYS;
		if (!OLIsListEmpty(&dbgl_clients[DBGL_CHANGES]))
			dbgl_out[i++] = DBGL_CHANGES;
		if (!OLIsListEmpty(&dbgl_clients[DBGL_ALL]))
			dbgl_out[i++] = DBGL_ALL;

		if (check_len)
			mute_dbgl_sys = check_dbg_history(DBGL_SYS, s, expire, check_len);

		if (mute_dbgl_sys != DBG_HIST_MUTED)
			syslog(mapSyslogPrio(dbgt), "%s%s%s%s\n", dbgt2str[dbgt], f ? f : "", f ? "(): " : "", s);

		if (mute_dbgl_sys == DBG_HIST_MUTING)
			syslog(mapSyslogPrio(dbgt), "%smuting further messages (with equal first %d bytes) for at most %d seconds\n",
						 dbgt2str[DBGT_WARN], check_len, expire / 1000);
	}

	for (j = 0; j < i; j++)
	{
		int level = dbgl_out[j];

		if (level == DBGL_ALL)
			dbgl_all_msg_num++;

		if (level == DBGL_CHANGES && check_len &&
				(mute_dbgl_changes = check_dbg_history(DBGL_CHANGES, s, expire, check_len)) == DBG_HIST_MUTED)
			continue;

		if (level == DBGL_SYS && mute_dbgl_sys == DBG_HIST_MUTED)
			continue;

		OLForEach(dn, struct dbgl_node, dbgl_clients[DBGL_ALL])
		{

			if (!dn->cn || dn->cn->fd <= 0)
				continue;

			if (level == DBGL_CHANGES ||
					level == DBGL_TEST ||
					level == DBGL_PROFILE ||
					level == DBGL_SYS)
				dbg_printf(dn->cn, "[%d %8llu] ", My_pid, (unsigned long long)batman_time);

			if (level == DBGL_ALL)
				dbg_printf(dn->cn, "[%d %8llu %5u] ", My_pid, (unsigned long long)batman_time, dbgl_all_msg_num);

		  snprintf(format,sizeof(format),"%%s%%.%ds %%s%%s%%s\n", indent);
			dbg_printf(dn->cn, format, dbgt2str[dbgt], space, f ? f : "", f ? "(): " : "", s);

			if ((level == DBGL_SYS && mute_dbgl_sys == DBG_HIST_MUTING) ||
					(level == DBGL_CHANGES && mute_dbgl_changes == DBG_HIST_MUTING))
				dbg_printf(dn->cn,
									 "[%d %8llu] %smuting further messages (with equal first %d bytes) for at most %d seconds\n",
									 My_pid, (unsigned long long)batman_time, dbgt2str[DBGT_WARN], check_len, expire / 1000);
		}
	}
}

// this static array of char is used by all following dbg functions.
static char dbg_string_out[MAX_DBG_STR_SIZE + 1];

void dbg(int8_t dbgl, int8_t dbgt, char *last, ...)
{
	va_list ap;
	va_start(ap, last);
	vsnprintf(dbg_string_out, MAX_DBG_STR_SIZE, last, ap);
	va_end(ap);
	debug_output(0, 0, 0, 0, dbgl, dbgt, 0, dbg_string_out);
}

void _dbgf(int8_t dbgl, int8_t dbgt, char const *f, char *last, ...)
{
	va_list ap;
	va_start(ap, last);
	vsnprintf(dbg_string_out, MAX_DBG_STR_SIZE, last, ap);
	va_end(ap);
	debug_output(0, 0, 0, 0, dbgl, dbgt, f, dbg_string_out);
}

void dbg_cn(struct ctrl_node *cn, int8_t dbgl, int8_t dbgt, char *last, ...)
{
	va_list ap;
	va_start(ap, last);
	vsnprintf(dbg_string_out, MAX_DBG_STR_SIZE, last, ap);
	va_end(ap);
	debug_output(0, 0, 0, cn, dbgl, dbgt, 0, dbg_string_out);
}

void _dbgf_cn(struct ctrl_node *cn, int8_t dbgl, int8_t dbgt, char const *f, char *last, ...)
{
	va_list ap;
	va_start(ap, last);
	vsnprintf(dbg_string_out, MAX_DBG_STR_SIZE, last, ap);
	va_end(ap);
	debug_output(0, 0, 0, cn, dbgl, dbgt, f, dbg_string_out);
}

void dbg_mute(uint8_t indent, uint32_t check_len, int8_t dbgl, int8_t dbgt, char *last, ...)
{
	va_list ap;
	va_start(ap, last);
	vsnprintf(dbg_string_out, MAX_DBG_STR_SIZE, last, ap);
	va_end(ap);
	debug_output(indent, check_len, dbg_mute_to, 0, dbgl, dbgt, 0, dbg_string_out);
}

#ifndef NODEBUGALL
void _dbgf_all(uint8_t indent, int8_t dbgt, char const *f, char *last, ...)
{
	va_list ap;
	va_start(ap, last);
	vsnprintf(dbg_string_out, MAX_DBG_STR_SIZE, last, ap);
	va_end(ap);
	debug_output(indent, 0, 0, 0, DBGL_ALL, dbgt, f, dbg_string_out);
}

uint8_t __dbgf_all(void)
{
	if (debug_level != DBGL_ALL && OLIsListEmpty(&dbgl_clients[DBGL_ALL]))
		return NO;

	return YES;
}
#endif //NODEBUGALL

int (*load_config_cb)(uint8_t test, struct opt_type *opt, struct ctrl_node *cn) = NULL;

int (*save_config_cb)(uint8_t del, struct opt_type *opt, char *parent, char *val, struct ctrl_node *cn) = NULL;

int (*derive_config)(char *reference, char *derivation, struct ctrl_node *cn) = NULL;

void get_init_string(int g_argc, char **g_argv)
{
	uint32_t size = 1;
	uint32_t dbg_init_out = 0;
	int i = 0;
	char *dbg_init_str = NULL;

	for (i = 0; i < g_argc; i++)
		size += (1 + strlen(g_argv[i]));

	dbg_init_str = debugMalloc(size, 127);

	for (i = 0; i < g_argc; i++)
		dbg_init_out = dbg_init_out + sprintf((dbg_init_str + dbg_init_out), "%s ", g_argv[i]);

	init_string = dbg_init_str;
}

static void free_init_string(void)
{
	if (init_string)
		debugFree(init_string, 1127);

	init_string = NULL;
}

int32_t get_tracked_network(struct opt_type *opt, struct opt_parent *patch, char *out, uint32_t *ip, int32_t *mask, struct ctrl_node *cn)
{
	struct opt_child *nc, *mc;
	struct opt_parent *p = get_opt_parent_val(opt, patch->p_val);

	if (!p || !(nc = get_opt_child(get_option(opt, 0, ARG_NETW), p)) || !nc->c_val)
		return FAILURE;

	if (!p || !(mc = get_opt_child(get_option(opt, 0, ARG_MASK), p)) || !mc->c_val)
		return FAILURE;

	sprintf(out, "%s/%s", nc->c_val, mc->c_val);

	if (str2netw(out, ip, '/', cn, mask, 32) == FAILURE)
		return FAILURE;

	return SUCCESS;
}

int32_t adj_patched_network(struct opt_type *opt, struct opt_parent *patch, char *out, uint32_t *ip, int32_t *mask, struct ctrl_node *cn)
{
	struct opt_child *nc, *mc;
	struct opt_parent *p;

	if (strpbrk(patch->p_val, "*'\"#\\/~?^°,;|<>()[]{}$%&=`´"))
	{
		dbg_cn(cn, DBGL_SYS, DBGT_ERR,
					 "%s %s with /%s and /%s MUST NOT be named with special characters or a leading number",
					 opt->long_name, patch->p_val, ARG_MASK, ARG_NETW);
		return FAILURE;
	}

	p = get_opt_parent_val(opt, patch->p_val);

	if ((mc = get_opt_child(get_option(opt, 0, ARG_MASK), patch)) && mc->c_val)
	{
		if (str2netw(mc->c_val, ip, '/', cn, 0, 0) == SUCCESS)
		{
			if (*ip == htonl(0xFFFFFFFF << (32 - (*mask = get_set_bits(*ip)))))
			{
				sprintf(out, "%d", *mask);
				set_opt_child_val(mc, out);
			}
			else
			{
				dbg_cn(cn, DBGL_SYS, DBGT_ERR, "invalid %s %s /%s %s",
							 opt->long_name, patch->p_val, ARG_MASK, mc->c_val);
				return FAILURE;
			}
		}
		else if ((*mask = strtol(mc->c_val, NULL, 10)))
		{
			if (*mask < MIN_MASK || *mask > MAX_MASK)
			{
				dbg_cn(cn, DBGL_SYS, DBGT_ERR, "invalid prefix-length %s %s /%s %s",
							 opt->long_name, patch->p_val, ARG_MASK, mc->c_val);
				return FAILURE;
			}
		}
		else
		{
			dbg_cn(cn, DBGL_SYS, DBGT_ERR, "missing prefix-length %s %s /%s %s",
						 opt->long_name, patch->p_val, ARG_MASK, mc->c_val);
			return FAILURE;
		}
	}
	else if (p && (mc = get_opt_child(get_option(opt, 0, ARG_MASK), p)) && mc->c_val)
	{
		*mask = strtol(mc->c_val, NULL, 10);
	}
	else
	{
		dbg_cn(cn, DBGL_SYS, DBGT_ERR, "missing %s %s /%s",
					 opt->long_name, patch->p_val, ARG_MASK);
		return FAILURE;
	}

	if ((nc = get_opt_child(get_option(opt, 0, ARG_NETW), patch)) && nc->c_val)
	{
		sprintf(out, "%s/%d", nc->c_val, *mask);
		if (str2netw(out, ip, '/', cn, mask, 32) == FAILURE)
		{
			dbg_cn(cn, DBGL_SYS, DBGT_ERR, "invalid patch %s %s /%s %s",
						 opt->long_name, patch->p_val, ARG_NETW, mc->c_val);
			return FAILURE;
		}

		set_opt_child_val(nc, ipStr(validate_net_mask(*ip, *mask, 0)));
	}
	else if (p && (nc = get_opt_child(get_option(opt, 0, ARG_NETW), p)) && nc->c_val)
	{
		sprintf(out, "%s/%d", nc->c_val, *mask);
		if (str2netw(out, ip, '/', cn, mask, 32) == FAILURE)
		{
			dbg_cn(cn, DBGL_SYS, DBGT_ERR, "invalid trac %s %s /%s %s",
						 opt->long_name, patch->p_val, ARG_NETW, mc->c_val);
			return FAILURE;
		}
	}
	else
	{
		dbg_cn(cn, DBGL_SYS, DBGT_ERR, "missing %s %s /%s",
					 opt->long_name, patch->p_val, ARG_NETW);

		return FAILURE;
	}

	sprintf(out, "%s/%d", nc->c_val, *mask);
	return SUCCESS;
}

static char *nextword(char *s)
{
	uint32_t i = 0;
	uint8_t found_gap = NO;

	if (!s)
		return NULL;

	for (i = 0; i < strlen(s); i++)
	{
		if (s[i] == '\0' || s[i] == '\n')
			return NULL;

		if (!found_gap && (s[i] == ' ' || s[i] == '\t'))
			found_gap = YES;

		if (found_gap && (s[i] != ' ' && s[i] != '\t'))
			return &(s[i]);
	}

	return NULL;
}

static char *debugWordDup(char *word, int32_t tag)
{
	if (!word)
		return NULL;

	char *ret = debugMalloc(wordlen(word) + 1, tag);
	snprintf(ret, wordlen(word) + 1, "%s", word);
	return ret;
}

static void strchange(char *s, char i, char o)
{
	char *p;
	while (s && (p = strchr(s, i)))
		p[0] = o;
}

static int32_t end_of_cmd_stream(struct opt_type *opt, char *s)
{
	char test[MAX_ARG_SIZE] = "";
	snprintf(test, wordlen(s) + 1, "%s", s);
	strchange(test, '-', '_');

	if (opt->opt_t != A_PS0)
		s = nextword(s);
	else if (wordlen(s) > 1 && !strncasecmp(test, opt->long_name, wordlen(opt->long_name)))
		s = nextword(s);
	else if (wordlen(s) > 1)
		s = s + 1;
	else
		s = nextword(s);

	if (s && (s[0] != EOS_DELIMITER || wordlen(s) > 1))
		return NO;

	return YES;
}

static int8_t is_valid_opt_ival(struct opt_type *opt, char *s, struct ctrl_node *cn)
{
	if (opt->imin == opt->imax)
		return SUCCESS;

	char *invalids = NULL;

	errno = 0;
	int ival = strtol(s, &invalids, 10);

	if (wordlen(s) < 1 ||
			ival < opt->imin || ival > opt->imax ||
			invalids != (s + wordlen(s)) ||
			errno == ERANGE || errno == EINVAL)
	{
		dbg_cn(cn, DBGL_SYS, DBGT_ERR, "--%s value %d is invalid! Must be %d <= <value> <= %d !",
					 opt->long_name, ival, opt->imin, opt->imax);

		return FAILURE;
	}

	return SUCCESS;
}

/*
 * call given function for each applied option
*/
int8_t func_for_each_opt(struct ctrl_node *cn, void *data, char *func_name,
												 int8_t (*func)(struct ctrl_node *cn, void *data, struct opt_type *opt, struct opt_parent *p, struct opt_child *c))
{
	OLForEach(opt, struct opt_type, opt_list)
	{

		if (/* !opt->help  || we are also interested in uncommented configurations*/ !opt->long_name)
			continue;

		OLForEach(p, struct opt_parent, opt->d.parents_instance_list)
		{

			if ((*func)(cn, data, opt, p, NULL) == FAILURE)
			{
				dbgf_cn(cn, DBGL_SYS, DBGT_ERR,
								"func()=%s with %s %s failed",
								func_name, opt->long_name, p->p_val);

				return FAILURE;
			}

			OLForEach(c, struct opt_child, p->childs_instance_list)
			{

				if ((*func)(cn, data, opt, p, c) == FAILURE)
				{
					dbgf_cn(cn, DBGL_SYS, DBGT_ERR,
									"func()=%s with %s %s %s %s failed",
									func_name, opt->long_name, p->p_val, c->c_opt->long_name, c->c_val);

					return FAILURE;
				}
			}
		}
	}

	return SUCCESS;
}

static void show_opts_help(struct ctrl_node *cn)
{
	if (!cn)
		return;

	dbg_printf(cn, "\n");
	dbg_printf(cn, "Usage: %s [LONGOPT[=[%c]VAL]] | [-SHORTOPT[SHORTOPT...] [[%c]VAL]] ...\n",
						 prog_name, ARG_RESET_CHAR, ARG_RESET_CHAR);
	dbg_printf(cn, "  e.g. %s dev=eth0 dev=wlan0         # to start daemon on interface eth0 and wlan0\n", prog_name);
	dbg_printf(cn, "  e.g. %s -cid8                      # to connect and show configured options and connevtivity\n", prog_name);
	dbg_printf(cn, "\n");

	OLForEach(opt, struct opt_type, opt_list)
	{
		char sn[5], st[3 * MAX_ARG_SIZE], defaults[100];

		if (opt->long_name && opt->help && !opt->parent_name)
		{
			if (opt->short_name)
				snprintf(sn, 5, ", -%c", opt->short_name);
			else
				*sn = '\0';

			sprintf(st, "--%s%s %s ", opt->long_name, sn, opt->syntax ? opt->syntax : "");

			if (opt->opt_t != A_PS0 && opt->imin != opt->imax)
				sprintf(defaults, "def: %-6d  range: [ %d %s %d ]",
								opt->idef, opt->imin, opt->imin + 1 == opt->imax ? "," : "...", opt->imax);
			else
				defaults[0] = '\0';

			dbg_printf(cn, "\n%-40s %s\n", st, defaults);
			dbg_printf(cn, "	%s\n", opt->help);
		}
		else if (!opt->long_name && opt->help)
		{
			dbg_printf(cn, "\n%s \n", opt->help);
		}

		OLForEach(c_opt, struct opt_type, opt->d.childs_type_list)
		{

			if (!c_opt->parent_name || !c_opt->help)
				continue;

			if (c_opt->short_name)
				snprintf(sn, 5, ", /%c", c_opt->short_name);
			else
				*sn = '\0';

			sprintf(st, "  /%s%s %s ", c_opt->long_name, sn, c_opt->syntax ? c_opt->syntax : "");

			if (c_opt->opt_t != A_PS0 && c_opt->imin != c_opt->imax)
				sprintf(defaults, "def: %-6d  range: [ %d %s %d ]",
								c_opt->idef, c_opt->imin, c_opt->imin + 1 == c_opt->imax ? "," : "...", c_opt->imax);
			else
				defaults[0] = '\0';

			dbg_printf(cn, "%-40s %s\n", st, defaults);
			dbg_printf(cn, "	        %s\n", c_opt->help);
		}
	}
}

void register_option(struct opt_type *opt)
{
	dbgf_all(0, DBGT_INFO, "%s", (opt && opt->long_name) ? opt->long_name : "");

	// these are the valid combinations:
	if (!(
					//ival is validated and if valid assigned by call_option()
					((opt->ival) && (opt->call_custom_option) && (opt->long_name)) ||
					//ival is validated and if valid assigned
					((opt->ival) && !(opt->call_custom_option) && (opt->long_name)) ||
					//call_option() is called
					(!(opt->ival) && (opt->call_custom_option) && (opt->long_name)) ||
					//
					(!(opt->ival) && !(opt->call_custom_option) && !(opt->long_name) && opt->help)))
		goto failure;

	// arg_t A_PS0 with no function can only be YES/NO:
	paranoia(-500111, (opt->opt_t == A_PS0 && opt->ival && (opt->imin != NO || opt->imax != YES || opt->idef != NO)));

	// arg_t A_PS0 can not be stored
	paranoia(-500112, (opt->opt_t == A_PS0 && opt->cfg_t != A_ARG));

	paranoia(-500113, (opt->order < 0 || opt->order > 99));

	paranoia(-500114, ((opt->parent_name && strchr(opt->parent_name, '-')) || (opt->long_name && strchr(opt->long_name, '-'))));

	memset(&(opt->d), 0, sizeof(struct opt_data));

	if (opt->ival)
		*opt->ival = opt->idef;

	if (opt->parent_name)
	{
		struct opt_type *tmp_opt = NULL;
		OLForEach(tmp, struct opt_type, opt_list)
		{
			if (tmp->long_name == opt->parent_name)
			{
				tmp_opt = tmp;
				break;
			}
		}

		if (opt->opt_t != A_CS1 || !tmp_opt || tmp_opt->opt_t != A_PMN)
			goto failure;

		opt->d.parent_opt = tmp_opt;

		OLInitializeListHead(&opt->d.list);
		OLInsertTailList(&tmp_opt->d.childs_type_list, &opt->d.list);
	}
	else
	{
		int inserted = 0;
		OLInitializeListHead(&opt->d.list);
		OLInitializeListHead(&opt->d.childs_type_list);
		OLInitializeListHead(&opt->d.parents_instance_list);

		//insert option sorted
		if (opt->order)
		{
			//run through sorted list and find new position
			OLForEach(tmp_opt, struct opt_type, opt_list)
			{

				if (tmp_opt->order > opt->order)
				{
					//add new option before current
					OLInsertTailList((PLIST_ENTRY)tmp_opt, &opt->d.list);
					inserted = 1;
					break;
				}
			}
		}

		if (!inserted)
			OLInsertTailList(&opt_list, &opt->d.list);
	}

	if (opt->call_custom_option && ((opt->call_custom_option)(OPT_REGISTER, 0, opt, 0, 0)) == FAILURE)
	{
		dbgf(DBGL_SYS, DBGT_ERR, "%s failed!", opt->long_name);
		goto failure;
	}

	return;

failure:

	dbgf(DBGL_SYS, DBGT_ERR, "invalid data,  option %c %s",
			 (opt && opt->short_name) ? opt->short_name : '?', (opt && opt->long_name) ? opt->long_name : "??");

	paranoia(-500091, YES);
}

static void remove_option(struct opt_type *opt)
{

	del_opt_parent(opt, NULL);

	OLForEach(tmp_opt, struct opt_type, opt_list)
	{
		if (opt == tmp_opt)
		{
			if (!opt->parent_name && opt->call_custom_option &&
					((opt->call_custom_option)(OPT_UNREGISTER, 0, opt, 0, 0)) == FAILURE)
			{
				dbgf(DBGL_SYS, DBGT_ERR, "%s failed!", opt->long_name);
			}

			OLRemoveEntry(tmp_opt);
			return;
		}
	}

	dbgf(DBGL_SYS, DBGT_ERR, "%s no matching opt found", opt->long_name);
}

void register_options_array(struct opt_type *fixed_options, int size)
{
	int i = 0;
	int i_max = size / sizeof(struct opt_type);

	paranoia(-500149, ((size % sizeof(struct opt_type)) != 0));

	while (i < i_max && (fixed_options[i].long_name || fixed_options[i].help))
		register_option(&(fixed_options[i++]));
}

struct opt_type *get_option(struct opt_type *parent_opt, uint8_t short_opt, char *sin)
{
	int32_t len = 0;
	PLIST_ENTRY list;
	struct opt_type *opt = NULL;
	char *equalp = NULL;
	char s[MAX_ARG_SIZE] = "";

	if (parent_opt && short_opt)
		goto get_option_failure;

	if (!sin || wordlen(sin) + 1 >= MAX_ARG_SIZE)
		goto get_option_failure;

	snprintf(s, wordlen(sin) + 1, "%s", sin);
	strchange(s, '-', '_');

	if (short_opt)
		len = 1;
	else if ((equalp = index(s, '=')) && equalp < s + wordlen(s))
		len = equalp - s;
	else
		len = wordlen(s);

	if (parent_opt == NULL)
		list = &opt_list;
	else
		list = &parent_opt->d.childs_type_list;

	dbgf_all(0, DBGT_INFO, "searching %s", s);

	//list is a pointer, but macro needs the object self
	OLForEach(tmp_opt, struct opt_type, *list)
	{
		opt = tmp_opt;

		if (!opt->long_name)
			continue;

		else if (!short_opt && len == (int)strlen(opt->long_name) && !strncasecmp(s, opt->long_name, len))
			break;

		else if (!short_opt && len == 1 && s[0] == opt->short_name && on_the_fly && opt->dyn_t != A_INI)
			break;

		else if (!short_opt && len == 1 && s[0] == opt->short_name && !on_the_fly && opt->dyn_t != A_DYN)
			break;

		else if (short_opt && s[0] == opt->short_name && on_the_fly && opt->dyn_t != A_INI)
			break;

		else if (short_opt && s[0] == opt->short_name && !on_the_fly && opt->dyn_t != A_DYN)
			break;

		opt = NULL;
	}

	if (opt && opt->long_name)
	{
		dbgf_all(0, DBGT_INFO,
						 "Success! short_opt %d, opt: %s %c, type %d, dyn %d, ival %d, imin %d, imax %d, idef %d",
						 short_opt, opt->long_name ? opt->long_name : "-", opt->short_name ? opt->short_name : '-',
						 opt->opt_t, opt->dyn_t,
						 opt->ival ? *opt->ival : 0, opt->imin, opt->imax, opt->idef);

		return opt;
	}

get_option_failure:

	dbgf_all(0, DBGT_WARN, "Failed! called with parent %s, opt %c %s, len %d",
					 parent_opt ? "YES" : "NO", (short_opt ? s[0] : '-'), (!short_opt ? s : "-"), len);

	return NULL;
}

struct opt_child *get_opt_child(struct opt_type *opt, struct opt_parent *p)
{

	paranoia(-500026, (opt->opt_t != A_CS1));

	paranoia(-500119, (!p));

	OLForEach(c, struct opt_child, p->childs_instance_list)
	{

		if (c->c_opt == opt)
			return c;
	}

	return NULL;
}

void set_opt_child_val(struct opt_child *c, char *val)
{
	if (val && c->c_val && wordsEqual(c->c_val, val))
		return;

	if (c->c_val)
		debugFree(c->c_val, 1789);

	c->c_val = NULL;

	if (val)
		c->c_val = debugWordDup(val, 789);
}

static void set_opt_child_ref(struct opt_child *c, char *ref)
{
	if (ref && c->c_ref && wordsEqual(c->c_ref, ref))
		return;

	if (c->c_ref)
		debugFree(c->c_ref, 1789);

	c->c_ref = NULL;

	if (ref)
		c->c_ref = debugWordDup(ref, 789);
}

static void del_opt_child_save(struct opt_child *c)
{

	set_opt_child_val(c, NULL);
	set_opt_child_ref(c, NULL);
}

static void del_opt_child(struct opt_parent *p, struct opt_type *opt)
{
	OLForEach(c, struct opt_child, p->childs_instance_list)
	{

		if (!opt || c->c_opt == opt)
		{
			PLIST_ENTRY prev = OLGetPrev(c);
			del_opt_child_save(c);
			OLRemoveEntry(c);
			debugFree(c, 1787);
			c = (struct opt_child *)prev;
		}
	}
}

static struct opt_child *add_opt_child(struct opt_type *opt, struct opt_parent *p)
{
	struct opt_child *c = debugMalloc(sizeof(struct opt_child), 787);
	memset(c, 0, sizeof(struct opt_child));
	OLInitializeListHead(&c->list);

	c->c_opt = opt;
	c->parent_instance = p;
	OLInsertTailList(&p->childs_instance_list, &c->list);

	return c;
}

void set_opt_parent_val(struct opt_parent *p, char *val)
{
	if (val && p->p_val && wordsEqual(p->p_val, val))
		return;

	if (p->p_val)
		debugFree(p->p_val, 1778);

	p->p_val = NULL;

	if (val)
		p->p_val = debugWordDup(val, 778);
}

void set_opt_parent_ref(struct opt_parent *p, char *ref)
{
	if (ref && p->p_ref && wordsEqual(p->p_ref, ref))
		return;

	if (p->p_ref)
		debugFree(p->p_ref, 1779);

	p->p_ref = NULL;

	if (ref)
		p->p_ref = debugWordDup(ref, 779);
}

struct opt_parent *add_opt_parent(struct opt_type *opt)
{
	struct opt_parent *p = debugMalloc(sizeof(struct opt_parent), 777);
	memset(p, 0, sizeof(struct opt_parent));
	OLInitializeListHead(&p->list);
	OLInitializeListHead(&p->childs_instance_list);

	opt->d.found_parents++;

	OLInsertTailList(&opt->d.parents_instance_list, &p->list);

	return p;
}

static void del_opt_parent_save(struct opt_type *opt, struct opt_parent *p)
{

	opt->d.found_parents--;

	del_opt_child(p, NULL);

	set_opt_parent_val(p, NULL);
	set_opt_parent_ref(p, NULL);
}

void del_opt_parent(struct opt_type *opt, struct opt_parent *parent)
{
	OLForEach(p, struct opt_parent, opt->d.parents_instance_list)
	{

		if (!parent || p == parent)
		{
			PLIST_ENTRY prev = OLGetPrev(p);
			del_opt_parent_save(opt, p);
			OLRemoveEntry(p);
			debugFree(p, 1777);
			p = (struct opt_parent *)prev;
		}
	}
}

struct opt_parent *get_opt_parent_val(struct opt_type *opt, char *val)
{

	paranoia(-500118, (opt->cfg_t == A_ARG));

	paranoia(-500117, ((opt->opt_t == A_PS0 || opt->opt_t == A_PS1) && opt->d.found_parents > 1));

	OLForEach(p, struct opt_parent, opt->d.parents_instance_list)
	{

		if (!val || wordsEqual(p->p_val, val))
			return p;
	}

	return NULL;
}

struct opt_parent *get_opt_parent_ref(struct opt_type *opt, char *ref)
{

	paranoia(-500124, (opt->cfg_t == A_ARG));

	paranoia(-500116, ((opt->opt_t == A_PS0 || opt->opt_t == A_PS1) && opt->d.found_parents > 1));

	OLForEach(p, struct opt_parent, opt->d.parents_instance_list)
	{

		if (ref && wordsEqual(p->p_ref, ref))
			return p;
	}

	return NULL;
}

static struct opt_parent *dup_opt_parent(struct opt_type *opt, struct opt_parent *p)
{
	struct opt_parent *dup_p = add_opt_parent(opt);
	set_opt_parent_val(dup_p, p->p_val);
	set_opt_parent_ref(dup_p, p->p_ref);

	dup_p->p_diff = p->p_diff;

	OLForEach(c, struct opt_child, p->childs_instance_list)
	{

		struct opt_child *dup_c = add_opt_child(c->c_opt, dup_p);
		set_opt_child_val(dup_c, c->c_val);
		set_opt_child_ref(dup_c, c->c_ref);
	}

	return dup_p;
}

char *opt_cmd2str[] = {
		"OPT_REGISTER",
		"OPT_PATCH",
		"OPT_ADJUST",
		"OPT_CHECK",
		"OPT_APPLY",
		"OPT_SET_POST",
		"OPT_POST",
		"OPT_UNREGISTER"};

int32_t check_apply_parent_option(uint8_t del, uint8_t cmd, uint8_t _save, struct opt_type *opt, char *in, struct ctrl_node *cn)
{
	int32_t ret;

	//add null pointer check
	paranoia(-500102, ((cmd != OPT_CHECK && cmd != OPT_APPLY) || !opt || opt->parent_name));

	struct opt_parent *p = add_opt_parent(&Patch_opt);

	if ((ret = call_option(del, OPT_PATCH, _save, opt, p, in, cn)) == FAILURE ||
			call_option(del, OPT_ADJUST, _save, opt, p, in, cn) == FAILURE ||
			call_option(del, cmd, _save, opt, p, in, cn) == FAILURE)
		ret = FAILURE;

	del_opt_parent(&Patch_opt, p);

	dbgf_all(0, DBGT_INFO, "del:%d, %s, save:%d, %s %s returns: %d",
					 del, opt_cmd2str[cmd], _save, opt->long_name, in, ret);

	return ret;
}

static int32_t call_opt_patch(uint8_t ad, struct opt_type *opt, struct opt_parent *patch, char *strm, struct ctrl_node *cn)
{
	dbgf_all(0, DBGT_INFO, "ad:%d opt:%s val:%s strm:%s",
					 ad, opt->long_name, patch->p_val, strm);

	if (opt->opt_t == A_PS0)
	{
		patch->p_diff = ((ad == ADD) ? ADD : DEL);
	}
	else if (opt->opt_t == A_PS1 || opt->opt_t == A_PMN || opt->opt_t == A_CS1)
	{
		char *ref = NULL;
		char tmp[MAX_ARG_SIZE];

		// assign one or more values
		if (ad == ADD || opt->opt_t == A_PMN)
		{
			if (!strm || !wordlen(strm) || strm[0] == EOS_DELIMITER)
				return FAILURE;

			if (strm && wordlen(strm) > strlen(REFERENCE_KEY_WORD) &&
					!strncmp(strm, REFERENCE_KEY_WORD, strlen(REFERENCE_KEY_WORD)))
			{
				ref = strm;

				if (ad == ADD)
				{
					if (!derive_config || derive_config(ref, tmp, cn) == FAILURE || !wordlen(strm))
					{
						dbg_cn(cn, DBGL_SYS, DBGT_ERR,
									 "%s. Could not derive reference %s",
									 derive_config ? "invalid config" : "undefined callback", strm);
						return FAILURE;
					}

					strm = tmp;
				}
				else if (ad == DEL)
				{
					struct opt_parent *p_track = get_opt_parent_ref(opt, strm);

					if (!p_track || !p_track->p_val)
					{
						dbg_cn(cn, DBGL_SYS, DBGT_ERR,
									 "Could not derive reference %s from tracked options", strm);
						return FAILURE;
					}

					strm = p_track->p_val;
				}
			}

			if (is_valid_opt_ival(opt, strm, cn) == FAILURE)
				return FAILURE;
		}

		if (opt->opt_t == A_PS1 || opt->opt_t == A_PMN)
		{
			set_opt_parent_val(patch, strm);
			set_opt_parent_ref(patch, ref);

			patch->p_diff = ((ad == ADD) ? ADD : DEL);
		}
		else if (opt->opt_t == A_CS1)
		{
			struct opt_child *c = add_opt_child(opt, patch);

			if (ad == ADD)
				set_opt_child_val(c, strm);

			set_opt_child_ref(c, ref);
		}
	}

	return SUCCESS;
}

static int32_t cleanup_patch(struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	uint8_t del = patch->p_diff;
	char *val = patch->p_val;

	dbgf_all(0, DBGT_INFO, "del %d  opt %s  val %s", del, opt->long_name, val);

	if (opt->cfg_t == A_ARG)
		return SUCCESS;

	if (opt->opt_t == A_PS0)
	{
		if ((del && !opt->d.found_parents) || (!del && opt->d.found_parents))
			patch->p_diff = NOP;
	}
	else if (opt->opt_t == A_PS1)
	{
		if ((del && !opt->d.found_parents) || (!del && get_opt_parent_val(opt, val)))
			patch->p_diff = NOP;
	}
	else if (opt->opt_t == A_PMN)
	{
		struct opt_parent *p_track = NULL;

		OLForEach(c, struct opt_child, patch->childs_instance_list)
		{
			struct opt_child *c_track = NULL;
			uint8_t c_del = c->c_val ? ADD : DEL;

			p_track = NULL;

			dbgf_all(0, DBGT_INFO, "p_val:%s", patch->p_val);

			if ((p_track = get_opt_parent_val(opt, val)))
				c_track = get_opt_child(c->c_opt, p_track);

			if ((c_del && !c_track) ||
					(!c_del && c_track && wordsEqual(c_track->c_val, c->c_val)))
			{
				PLIST_ENTRY prev = OLGetPrev(c);
				del_opt_child_save(c);
				OLRemoveEntry(c);
				debugFree(c, 1787);
				c = (struct opt_child *)prev;
			}
		}

		p_track = get_opt_parent_val(opt, val);

		if ((del && !p_track) || (!del && p_track))
			patch->p_diff = NOP;
	}
	else
	{
		return FAILURE;
	}

	return SUCCESS;
}

static int32_t _opt_connect(uint8_t cmd, struct opt_type *opt, struct ctrl_node *cn, char *curr_strm_pos)
{
	char tmp_path[MAX_PATH_SIZE + 20] = "";
	char unix_buff[MAX_UNIX_MSG_SIZE + 1] = "";

	dbgf_all(0, DBGT_INFO, "cmd %s, opt_name %s, stream %s",
					 opt_cmd2str[cmd], opt->long_name, curr_strm_pos);

	if (cmd == OPT_CHECK || cmd == OPT_APPLY)
	{
		if (!curr_strm_pos)
			cleanup_all(-500141);

		sprintf(tmp_path, "%s/sock", run_dir);

		struct sockaddr_un unix_addr;

		memset(&unix_addr, 0, sizeof(struct sockaddr_un));
		unix_addr.sun_family = AF_LOCAL;
		strcpy(unix_addr.sun_path, tmp_path);

		if (strlen(curr_strm_pos) + 4 + strlen(ARG_TEST) > sizeof(unix_buff))
		{
			dbg(DBGL_SYS, DBGT_ERR, "message too long: %s", curr_strm_pos);
			cleanup_all(CLEANUP_FAILURE);
		}

		if (cmd == OPT_CHECK)
		{
			return SUCCESS;
		}

		Client_mode = YES;

		do
		{
			dbgf_all(0, DBGT_INFO, "called with %s", curr_strm_pos);

			if (strlen(curr_strm_pos) > strlen(ARG_CONNECT) &&
					!strncmp(curr_strm_pos, ARG_CONNECT, strlen(ARG_CONNECT)) &&
					(curr_strm_pos + strlen(ARG_CONNECT))[0] == ' ')
			{
				sprintf(unix_buff, "%s %c", nextword(curr_strm_pos), EOS_DELIMITER);
			}
			else if (strlen(curr_strm_pos) > strlen(ARG_CONNECT) &&
							 !strncmp(curr_strm_pos, ARG_CONNECT, strlen(ARG_CONNECT)) &&
							 (curr_strm_pos + strlen(ARG_CONNECT))[0] == '=')
			{
				sprintf(unix_buff, "%s %c", curr_strm_pos + strlen(ARG_CONNECT) + 1, EOS_DELIMITER);
			}
			else if (strlen(curr_strm_pos) > 1 && curr_strm_pos[0] == opt->short_name && curr_strm_pos[1] == ' ')
			{
				sprintf(unix_buff, "%s %c", nextword(curr_strm_pos), EOS_DELIMITER);
			}
			else if (strlen(curr_strm_pos) > 1 && curr_strm_pos[0] == opt->short_name && curr_strm_pos[1] != ' ')
			{
				sprintf(unix_buff, "-%s %c", curr_strm_pos + 1, EOS_DELIMITER);
			}
			else
			{
				dbgf_cn(cn, DBGL_SYS, DBGT_ERR, "invalid connect stream %s", curr_strm_pos);
				return FAILURE;
			}

			unix_sock = socket(AF_LOCAL, SOCK_STREAM, 0);

			/* make unix_sock socket non blocking */
			int sock_opts = fcntl(unix_sock, F_GETFL, 0);
			fcntl(unix_sock, F_SETFL, sock_opts | O_NONBLOCK);

			if (connect(unix_sock, (struct sockaddr *)&unix_addr, sizeof(struct sockaddr_un)) < 0)
			{
				dbg(DBGL_SYS, DBGT_ERR,
						"can't connect to unix socket '%s': %s ! Is bmxd running on this host ?",
						tmp_path, strerror(errno));

				cleanup_all(CLEANUP_FAILURE);
			}

			if (write(unix_sock, unix_buff, strlen(unix_buff)) < 0)
			{
				dbg(DBGL_SYS, DBGT_ERR, "can't write to unix socket: %s", strerror(errno));
				cleanup_all(CLEANUP_FAILURE);
			}

			//printf("::::::::::::::::: from %s begin :::::::::::::::::::\n", tmp_path );

			if (loop_mode)
				UNUSED_RETVAL(system("clear"));

			int32_t recv_buff_len = 0;

			while (!is_aborted())
			{
				recv_buff_len = 0;

				fd_set unix_wait_set;

				FD_ZERO(&unix_wait_set);
				FD_SET(unix_sock, &unix_wait_set);

				struct timeval to = {0, 100000};

				select(unix_sock + 1, &unix_wait_set, NULL, NULL, &to);

				if (!FD_ISSET(unix_sock, &unix_wait_set))
					continue;

				do
				{
					errno = 0;
					recv_buff_len = read(unix_sock, unix_buff, MAX_UNIX_MSG_SIZE);

					if (recv_buff_len > 0)
					{
						char *p;
						unix_buff[recv_buff_len] = '\0';

						if ((p = strchr(unix_buff, CONNECTION_END_CHR)))
						{
							*p = '\0';
							printf("%s", unix_buff);
							break;
						}

						printf("%s", unix_buff);
					}

				} while (recv_buff_len > 0);

				if (recv_buff_len < 0 && (errno == EWOULDBLOCK || errno == EAGAIN))
					continue;

				if (recv_buff_len < 0)
				{
					dbgf(DBGL_SYS, DBGT_INFO, "sock returned %d errno %d: %s",
							 recv_buff_len, errno, strerror(errno));
				}

				if (recv_buff_len <= 0)
					cleanup_all(CLEANUP_FAILURE);

				break;
			}

			close(unix_sock);
			unix_sock = 0;

			if (loop_mode && !is_aborted())
				bat_wait(DEF_LOOP_PERIOD / 1000, DEF_LOOP_PERIOD % 1000);

		} while (loop_mode && !is_aborted());

		cleanup_all(CLEANUP_SUCCESS);
	}

	return SUCCESS;
}

static int32_t opt_connect(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	char tmp_path[MAX_PATH_SIZE + 20] = "";

	if (cmd == OPT_SET_POST && !on_the_fly)
	{
		// create unix sock:

		struct sockaddr_un unix_addr;

		sprintf(tmp_path, "%s/sock", run_dir);

		memset(&unix_addr, 0, sizeof(struct sockaddr_un));
		unix_addr.sun_family = AF_LOCAL;
		strcpy(unix_addr.sun_path, tmp_path);

		// Testing for open and used unix socket

		unix_sock = socket(AF_LOCAL, SOCK_STREAM, 0);

		if (connect(unix_sock, (struct sockaddr *)&unix_addr, sizeof(struct sockaddr_un)) < 0)
		{
			dbgf_all(0, DBGT_INFO, "found unbound %s, going to unlink and reuse!", tmp_path);

			close(unix_sock);
			unlink(tmp_path);
			unix_sock = socket(AF_LOCAL, SOCK_STREAM, 0);
		}
		else
		{
			dbg(DBGL_SYS, DBGT_ERR,
					"%s busy! Probably bmxd is already running! Use [--%s %s] -c ... to connect to a running bmxd",
					tmp_path, ARG_RUN_DIR, run_dir);
			cleanup_all(CLEANUP_FAILURE);
		}

		if (bind(unix_sock, (struct sockaddr *)&unix_addr, sizeof(struct sockaddr_un)) < 0)
		{
			dbg(DBGL_SYS, DBGT_ERR, "can't bind unix socket '%s': %s", tmp_path, strerror(errno));
			cleanup_all(CLEANUP_FAILURE);
		}

		if (listen(unix_sock, 10) < 0)
		{
			dbg(DBGL_SYS, DBGT_ERR, "can't listen unix socket '%s': %s", tmp_path, strerror(errno));
			cleanup_all(CLEANUP_FAILURE);
		}

		if (update_pid_file() == FAILURE)
			return FAILURE;
	}

	return SUCCESS;
}

static int32_t call_opt_apply(uint8_t cmd, uint8_t save, struct opt_type *opt, struct opt_parent *_patch, char *in, struct ctrl_node *cn)
{
	paranoia(-500154, (cmd != OPT_CHECK && cmd != OPT_APPLY));

	//cleanup_patch will change the patch, so we'll work with a duplicate and destroy it afterwards
	struct opt_parent *patch = dup_opt_parent(&Patch_opt, _patch);

	dbgf_all(0, DBGT_INFO, "%s save=%d %s p_diff=%d p_val:%s p_ref:%s strm:%s",
					 opt_cmd2str[cmd], save, opt->long_name, patch->p_diff, patch->p_val, patch->p_ref, in);

	if (cleanup_patch(opt, patch, cn) == FAILURE)
		goto call_opt_apply_error;

	if (patch->p_diff == NOP && OLIsListEmpty(&(patch->childs_instance_list)))
	{
		del_opt_parent(&Patch_opt, patch);
		return SUCCESS;
	}

	// keep this check after cleanup_patch  and  p_diff==NOP and list_empty check to let config_reload
	// apply all unchanged options

	if ((!on_the_fly && opt->dyn_t == A_DYN) || (on_the_fly && opt->dyn_t == A_INI))
	{
		dbg_cn(cn, DBGL_SYS, DBGT_ERR, "--%s%s%c can %s be applied at startup",
					 opt->long_name, opt->short_name ? ", -" : "", opt->short_name ? opt->short_name : ' ',
					 on_the_fly ? "ONLY" : "NOT");

		goto call_opt_apply_error;
	}

	if (opt->call_custom_option == opt_connect)
	{
		if (_opt_connect(cmd, opt, cn, in) == FAILURE)
			goto call_opt_apply_error;
	}
	else if (cmd == OPT_CHECK)
	{
		if (opt->call_custom_option &&
				(opt->call_custom_option)(OPT_CHECK, save, opt, patch, cn) == FAILURE)
			goto call_opt_apply_error;
	}
	else if (cmd == OPT_APPLY)
	{
		if (opt->ival && patch->p_diff == DEL)
			*(opt->ival) = opt->idef;

		else if (opt->opt_t == A_PS0 && opt->ival && patch->p_diff == ADD)
			*(opt->ival) = opt->imax;

		else if (opt->opt_t != A_PS0 && opt->ival && patch->p_diff == ADD)
			*(opt->ival) = strtol(patch->p_val, NULL, 10);

		if (opt->call_custom_option &&
				(opt->call_custom_option)(OPT_APPLY, save, opt, patch, cn) == FAILURE)
		{
			dbg_cn(cn, DBGL_SYS, DBGT_ERR,
						 "failed setting the already succesfully tested option %s to %s",
						 opt->long_name, patch->p_val);

			// this may happen when:
			// - overwriting a config-file option with a startup-option (pain in the ass!)
			// - configuring the same PMN option twice in one command-line
			goto call_opt_apply_error;
		}

		if (opt->auth_t == A_ADM)
		{
			dbgf_all(0, DBGT_INFO, "--%-22s  %-30s  (%s order %d)",
							 opt->long_name, patch->p_val, opt_cmd2str[cmd], opt->order);
		}
	}

	del_opt_parent(&Patch_opt, patch);
	return SUCCESS;

call_opt_apply_error:

	del_opt_parent(&Patch_opt, patch);
	return FAILURE;
}

/* this table lists what could happen and how its' handled in track_opt_parent():

patch	tracked		patch	tracked		config-
p_val	t_val		p_ref	t_ref	->	file		track
						value:		value:	ref:

DEL/0	x		x	x		DEL		DEL	DEL	| if      ( !p_val && t_val )

DEL/0	NULL		x	x		NOP		NOP	NOP	| else if ( !p_val && !t_val )

A	A		A	A		NOP		NOP	NOP	| else if (  p_val  &&  p_val == t_val  &&  p_ref == t_ref )
A	A		0	0		NOP		NOP	NOP	|

										| else [if (  p_val  && (p_val != t_val  ||  p_ref != t_ref )]
										|
A	A		A	B		ref		value	ref	|	| if ( p_ref )
A	A		A	0		ref		value	ref	|	|
A	B/NULL		A	A	(*)	ref		value	ref	|	|
A	B/NULL		A	B	(-)	ref		value	ref	|	|
A	B/NULL		A	0	(-)	ref		value	ref	|	|
										|
A	A		0	B		value		value	0	|	| else [if( !p_ref)]
A	B/NULL		0	0		value		NOP	0	|	|
A	B/NULL		0	A	(*)	value		value	0	|	|

(*) in these cases, when configuring parent-options
we have to reset the old (currently active) tracked t_val option
before configuring the new patched p_val parent value
This has already been done during call_option( cmd==CHECK || cmd==APPLY )

(-) impossible to configue in one step for parent-options

*/
static int32_t track_opt_parent(uint8_t cmd, uint8_t save, struct opt_type *p_opt, struct opt_parent *p_patch, struct ctrl_node *cn)
{
	struct opt_parent *p_reftr = get_opt_parent_ref(p_opt, p_opt->opt_t == A_PMN ? p_patch->p_ref : NULL);
	struct opt_parent *p_track = get_opt_parent_val(p_opt, p_opt->opt_t == A_PMN ? p_patch->p_val : NULL);

	paranoia(-500125, (p_reftr && p_track && p_reftr != p_track));

	p_track = p_track ? p_track : p_reftr;

	dbgf_all(0, DBGT_INFO, "%s %s save=%d patch_diff:%d patch_val:%s patch_ref:%s track_val:%s track_ref:%s",
					 opt_cmd2str[cmd], p_opt->long_name, save, p_patch->p_diff,
					 p_patch->p_val, p_patch->p_ref, p_track ? p_track->p_val : "-", p_track ? p_track->p_ref : "-");

	if (p_patch->p_diff == DEL && p_track)
	{
		if (cmd == OPT_APPLY)
		{
			if (save && save_config_cb)
				save_config_cb(DEL, p_opt, p_track->p_ref ? p_track->p_ref : p_track->p_val, NULL, cn);

			del_opt_parent(p_opt, p_track);
		}
	}
	else
	{
		uint8_t changed = NO;

		if (p_patch->p_diff == DEL && !p_track)
		{
			if (save)
			{
				dbg_cn(cn, DBGL_SYS, DBGT_ERR, "--%s %s does not exist", p_opt->long_name, p_patch->p_val);
				return FAILURE;
			}

			return SUCCESS;
		}
		else if ((p_patch->p_diff == ADD && p_patch->p_val && p_track && wordsEqual(p_patch->p_val, p_track->p_val)) &&
						 ((p_patch->p_ref && p_track->p_ref && wordsEqual(p_patch->p_ref, p_track->p_ref)) ||
							(!p_patch->p_ref && !p_track->p_ref)))
		{
		}
		else if (p_patch->p_val /*&&  (patch_c->c_ref || !patch_c->c_ref)*/)
		{
			if (cmd == OPT_APPLY)
			{
				if (!p_track)
				{
					p_track = add_opt_parent(p_opt);
					set_opt_parent_val(p_track, p_patch->p_val);
					set_opt_parent_ref(p_track, p_patch->p_ref);
				}

				if (save && save_config_cb)
					save_config_cb(ADD, p_opt,
												 p_track->p_ref ? p_track->p_ref : p_track->p_val,
												 p_patch->p_ref ? p_patch->p_ref : p_patch->p_val, cn);

				set_opt_parent_val(p_track, p_patch->p_val);
				set_opt_parent_ref(p_track, p_patch->p_ref);
			}
			changed = YES;
		}
		else
		{
			paranoia(-500121, YES);
		}

		if (cmd == OPT_APPLY && changed && p_opt->auth_t == A_ADM)
			dbg_cn(cn, DBGL_CHANGES, DBGT_INFO, "--%-22s %c%-30s",
						 p_opt->long_name, p_patch->p_diff == DEL ? '-' : ' ', p_patch->p_val);

		if (p_track)
		{
			OLForEach(c_patch, struct opt_child, p_patch->childs_instance_list)
			{
				uint8_t changed_child = NO;
				char *save_val = p_track->p_ref ? p_track->p_ref : p_track->p_val;
				struct opt_child *c_track = get_opt_child(c_patch->c_opt, p_track);

				if (!c_patch->c_val && c_track)
				{
					if (cmd == OPT_APPLY)
					{
						if (save && save_config_cb && c_track->c_opt->cfg_t != A_ARG)
							save_config_cb(DEL, c_track->c_opt, save_val, c_track->c_ref ? c_track->c_ref : c_track->c_val, cn);

						del_opt_child(p_track, c_track->c_opt);
					}
					changed_child = changed = YES;
				}
				else if (!c_patch->c_val && !c_track)
				{
					if (save)
					{
						dbg_cn(cn, DBGL_SYS, DBGT_ERR, "--%s %s /%s does not exist",
									 p_opt->long_name, p_patch->p_val, c_patch->c_opt->long_name);
						return FAILURE;
					}
				}
				else if ((c_patch->c_val && c_track && wordsEqual(c_patch->c_val, c_track->c_val)) &&
								 ((c_patch->c_ref && c_track->c_ref && wordsEqual(c_patch->c_ref, c_track->c_ref)) ||
									(!c_patch->c_ref && !c_track->c_ref)))
				{
					dbgf_all(0, DBGT_INFO, "--%s %s /%s %s already configured",
									 p_opt->long_name, p_patch->p_val, c_patch->c_opt->long_name, c_patch->c_val);
				}
				else if (c_patch->c_val)
				{
					if (cmd == OPT_APPLY)
					{
						if (save && save_config_cb && c_patch->c_opt->cfg_t != A_ARG)
							save_config_cb(ADD, c_patch->c_opt, save_val, c_patch->c_ref ? c_patch->c_ref : c_patch->c_val, cn);

						if (!c_track)
							c_track = add_opt_child(c_patch->c_opt, p_track);

						set_opt_child_val(c_track, c_patch->c_val);
						set_opt_child_ref(c_track, c_patch->c_ref);
					}

					changed_child = changed = YES;
				}
				else
				{
					paranoia(-500122, YES);
				}

				if (cmd == OPT_APPLY && changed_child && c_patch->c_opt->auth_t == A_ADM)
					dbg_cn(cn, DBGL_CHANGES, DBGT_INFO, "--%-22s  %-30s  /%-22s %c%-30s",
								 p_opt->long_name, p_patch->p_val,
								 c_patch->c_opt->long_name, c_patch->c_val ? ' ' : '-', c_patch->c_val);
			}
		}
	}

	return SUCCESS;
}

int32_t call_option(uint8_t ad, uint8_t cmd, uint8_t save, struct opt_type *opt, struct opt_parent *patch, char *in, struct ctrl_node *cn)
{
	dbgf_all(0, DBGT_INFO, "%s (cmd %s  del %d  save %d  parent_name %s order %d) p_val: %s in: %s",
					 opt->long_name, opt_cmd2str[cmd], ad, save, opt->parent_name, opt->order, patch ? patch->p_val : "-", in);

	if (!opt) // might be NULL when referring to disabled plugin functionality
		return SUCCESS;

	paranoia(-500104, (!(ad == ADD || ad == DEL)));

	paranoia(-500103, ((cmd == OPT_PATCH || cmd == OPT_ADJUST || cmd == OPT_CHECK || cmd == OPT_APPLY) && !patch));

	paranoia(-500147, ((cmd == OPT_PATCH || cmd == OPT_ADJUST || cmd == OPT_CHECK || cmd == OPT_APPLY) && !cn));

	if ((cmd == OPT_PATCH || cmd == OPT_ADJUST || cmd == OPT_CHECK || cmd == OPT_APPLY) &&
			!cn->authorized && opt->auth_t == A_ADM)
	{
		dbg_cn(cn, DBGL_SYS, DBGT_ERR, "insufficient permissions to use command %s", opt->long_name);
		return FAILURE;
	}

	if (ad == DEL && (/*!on_the_fly this is what concurrent -r and -g configurations do || */
										/* opt->dyn_t == A_INI this is what conf-reload tries   ||*/ opt->cfg_t == A_ARG))
	{
		dbg(DBGL_SYS, DBGT_ERR, "option %s can not be resetted during startup!", opt->long_name);
		return FAILURE;
	}

	if ((opt->pos_t == A_END || opt->pos_t == A_ETE) && in && !end_of_cmd_stream(opt, in))
	{
		if (cn)
		{
			dbg_cn(cn, DBGL_CHANGES, DBGT_ERR, "--%s%s%c MUST be last option before line feed",
						 opt->long_name, opt->short_name ? ", -" : "", opt->short_name ? opt->short_name : ' ');
		}

		goto call_option_failure;
	}

	if (cmd == OPT_PATCH)
	{
		if ((call_opt_patch(ad, opt, patch, in, cn)) == FAILURE)
			goto call_option_failure;

		if ((opt->pos_t == A_EAT || opt->pos_t == A_ETE) && in)
			return strlen(in);
		else
			return SUCCESS;
	}
	else if (cmd == OPT_ADJUST)
	{
		if (opt->call_custom_option &&
				((opt->call_custom_option)(OPT_ADJUST, 0, opt, patch, cn)) == FAILURE)
			goto call_option_failure;
		else
			return SUCCESS;
	}
	else if (cmd == OPT_CHECK || cmd == OPT_APPLY)
	{
		paranoia(-500105, (opt->parent_name));

		paranoia(-500128, (opt->cfg_t != A_ARG && (opt->opt_t == A_PMN || patch->p_diff != DEL) && !patch->p_val));

		if (opt->cfg_t != A_ARG && opt->opt_t == A_PMN)
		{
			struct opt_parent *p_reftr = get_opt_parent_ref(opt, patch->p_ref);
			struct opt_parent *p_track = get_opt_parent_val(opt, patch->p_val);

			paranoia(-500129, (p_reftr && p_track && p_reftr != p_track));

			p_track = p_track ? p_track : p_reftr;

			if ((patch->p_diff == ADD && patch->p_val && p_track &&
					 !wordsEqual(patch->p_val, p_track->p_val)) &&
					(patch->p_ref || p_track->p_ref))
				check_apply_parent_option(DEL, cmd, save, opt, p_track->p_val, cn);
		}

		if ((call_opt_apply(cmd, save, opt, patch, in, cn)) == FAILURE)
			goto call_option_failure;

		if (opt->cfg_t != A_ARG && track_opt_parent(cmd, save, opt, patch, cn) == FAILURE)
			goto call_option_failure;

		return SUCCESS;
	}
	else if (cmd == OPT_SET_POST || cmd == OPT_POST)
	{
		if (opt->call_custom_option && ((opt->call_custom_option)(cmd, 0, opt, 0, cn)) == FAILURE)
			goto call_option_failure;

		return SUCCESS;
	}

call_option_failure:

	dbg_cn(cn, DBGL_SYS, DBGT_ERR,
				 "--%s  %s  Failed ! "
				 "( diff:%d ad:%d val:%d min:%d max:%d def:%d  %s %d %d %d )",
				 opt->long_name ? opt->long_name : "-", in ? in : "-",
				 patch ? patch->p_diff : -1,
				 ad, opt->ival ? *(opt->ival) : 0, opt->imin, opt->imax, opt->idef,
				 opt_cmd2str[cmd], opt->opt_t, on_the_fly, wordlen(in));

	return FAILURE;
}

int respect_opt_order(uint8_t test, int8_t last, int8_t next, struct opt_type *on, uint8_t load, uint8_t cmd, struct ctrl_node *cn)
{

	dbgf_all(0, DBGT_INFO, "%s, cmd: %s, last %d, next %d, opt %s  load %d",
					 opt_cmd2str[test], opt_cmd2str[cmd], last, next, on ? on->long_name : "???", load);

	paranoia(-500002, (test != OPT_CHECK && test != OPT_APPLY));

	paranoia(-500107, (cmd == OPT_CHECK || cmd == OPT_APPLY));

	if (next == 0)
		return last;

	if (last > next)
	{
		// debug which option caused the problems !
		dbg_cn(cn, DBGL_SYS, DBGT_ERR,
					 "--%s%s%c (order=%d option) MUST appear earlier in command sequence!",
					 on ? on->long_name : "???", on && on->short_name ? ", " : "", on && on->short_name ? on->short_name : ' ', next);

		return FAILURE;
	}

	if (last == next)
		return next;

	OLForEach(opt, struct opt_type, opt_list)
	{

		if (load && opt->order >= last + 1 && opt->order <= next)
		{
			if (load_config_cb && load_config_cb(test, opt, cn) == FAILURE)
			{
				dbgf_all(0, DBGT_ERR, "load_config_cb() %s failed",
								 opt->long_name);

				return FAILURE;
			}
		}

		if (test == OPT_APPLY && opt->order >= last && opt->order <= next - 1)
		{
			if (call_option(ADD, cmd, 0 /*save*/, opt, 0, 0, cn) == FAILURE)
			{
				dbg_cn(cn, DBGL_SYS, DBGT_ERR, "call_option() %s cmd %s failed",
							 opt->long_name, opt_cmd2str[cmd]);

				return FAILURE;
			}
		}
	}

	return next;
}

// if returns SUCCESS then fd might be closed ( called remove_ctrl_node( fd ) ) or not.
// if returns FAILURE then fd IS open and must be closed
int8_t apply_stream_opts(char *s, char *fallback_opt, uint8_t cmd, uint8_t load_cfg, struct ctrl_node *cn)
{
	enum
	{
		NEXT_OPT,					// 0
		NEW_OPT,					// 1
		SHORT_OPT,				// 2
		LONG_OPT,					// 3
		LONG_OPT_VAL,			// 4
		LONG_OPT_WHAT,		// 5
		LONG_OPT_ARG,			// 6
		LONG_OPT_ARG_VAL, // 7
	};

	//char *state2str[] = {"NEXT_OPT","NEW_OPT","SHORT_OPT","LONG_OPT","LONG_OPT_VAL","LONG_OPT_WHAT","LONG_OPT_ARG","LONG_OPT_ARG_VAL"};

	int8_t state = NEW_OPT;
	struct opt_type *opt = NULL;
	struct opt_type *opt_arg = NULL;
	char *equalp = NULL;
	char *pmn_s = NULL;
	int8_t order = 0;
	int32_t pb;
	char argument[MAX_ARG_SIZE];
	struct opt_parent *patch = NULL;

	if (cmd != OPT_CHECK && cmd != OPT_APPLY)
		return FAILURE;

	uint8_t del;

	Load_config = load_cfg;
	Testing = 0;

	while (s && strlen(s) >= 1)
	{
		dbgf_all(0, DBGT_INFO, "cmd: %-10s, state: 0x%X opt: %s, wordlen: %d rest: %s",
						 opt_cmd2str[cmd], state, opt ? opt->long_name : "null", wordlen(s), s);

		if (Testing)
		{
			Testing = 0;
			close_ctrl_node(CTRL_CLOSE_SUCCESS, cn);
			return SUCCESS;
		}

		if (state == NEXT_OPT)
		{
			// assumes s points to last successfully processed word or its following gap
			s = nextword(s);
			state = NEW_OPT;
		}
		else if (state == NEW_OPT && wordlen(s) >= 2 && s[0] == '-' && s[1] != '-')
		{
			s++;
			state = SHORT_OPT;
		}
		else if (state == NEW_OPT && wordlen(s) >= 3 && s[0] == '-' && s[1] == '-')
		{
			s += 2;
			state = LONG_OPT;
		}
		else if (state == NEW_OPT && wordlen(s) >= 1 && s[0] != '-' && s[0] != '/')
		{
			state = LONG_OPT;
		}
		else if (state == SHORT_OPT && wordlen(s) >= 1)
		{
			if (!(opt = get_option(NULL, YES, s)))
				goto apply_args_error;

			if ((order = respect_opt_order(cmd, order, opt->order, opt, Load_config, OPT_SET_POST, cn)) < 0)
				goto apply_args_error;

			if (opt->opt_t == A_PS0)
			{
				if ((pb = check_apply_parent_option(ADD, cmd, 0 /*save*/, opt, s, cn)) == FAILURE)
					goto apply_args_error;

				if (pb)
				{
					s += pb;
					state = NEXT_OPT;
				}
				else if (wordlen(s + 1) >= 1)
				{
					s++;
					state = SHORT_OPT;
				}
				else if (wordlen(s + 1) == 0)
				{
					s++;
					state = NEXT_OPT;
				}
				else
				{
					goto apply_args_error;
				}
			}
			else if (opt->opt_t == A_PS1 || opt->opt_t == A_PMN)
			{
				s++;

				if (wordlen(s) > 1 && s[0] == '=')
					s++;

				if (wordlen(s) == 0 && !(s = nextword(s)))
					goto apply_args_error;

				state = LONG_OPT_VAL;
			}
		}
		else if (state == LONG_OPT && wordlen(s) >= 1)
		{
			opt = get_option(NULL, NO, s);

			if (opt)
			{
				if ((order = respect_opt_order(cmd, order, opt->order, opt, Load_config, OPT_SET_POST, cn)) < 0)
					goto apply_args_error;

				if (opt->opt_t == A_PS0)
				{
					if ((pb = check_apply_parent_option(ADD, cmd, 0 /*save*/, opt, s, cn)) == FAILURE)
						goto apply_args_error;

					if (pb)
						s += pb;
					else
						s += wordlen(s);

					state = NEXT_OPT;
				}
				else if (opt->opt_t == A_PS1 || opt->opt_t == A_PMN)
				{
					equalp = index(s, '=');

					if (equalp && equalp < s + wordlen(s))
					{
						s = equalp + 1;
					}
					else
					{
						if ((s = nextword(s)) == NULL)
							goto apply_args_error;
					}

					state = LONG_OPT_VAL;
				}
				else
				{
					goto apply_args_error;
				}
			}
			else if (fallback_opt)
			{
				if (cmd == OPT_CHECK)
				{
					snprintf(argument, MIN(sizeof(argument), wordlen(s) + 1), "%s", s);

					dbg_cn(cn, DBGL_SYS, DBGT_WARN,
								 "Invalid argument: %s! Trying fallback option: --%s",
								 argument, fallback_opt);
				}

				opt = get_option(NULL, NO, fallback_opt);

				if (opt && (opt->opt_t == A_PS1 || opt->opt_t == A_PMN))
				{
					if ((order = respect_opt_order(cmd, order, opt->order, opt, Load_config, OPT_SET_POST, cn)) < 0)
						goto apply_args_error;

					state = LONG_OPT_VAL;
				}
				else
				{
					goto apply_args_error;
				}
			}
			else
			{
				goto apply_args_error;
			}
		}
		else if (state == LONG_OPT_VAL && wordlen(s) >= 1)
		{
			if (opt->opt_t == A_PS1)
			{
				s = s + (del = ((s[0] == ARG_RESET_CHAR) ? 1 : 0));

				if ((pb = check_apply_parent_option(del, cmd, (on_the_fly ? YES : NO) /*save*/, opt, s, cn)) == FAILURE)
					goto apply_args_error;

				s += pb;
				state = NEXT_OPT;
			}
			else if (opt->opt_t == A_PMN)
			{
				s = s + (del = ((s[0] == ARG_RESET_CHAR) ? 1 : 0));

				patch = add_opt_parent(&Patch_opt);

				if ((pb = call_option(del, OPT_PATCH, 0 /*save*/, opt, patch, s, cn)) == FAILURE)
					goto apply_args_error;

				pmn_s = s;
				s += pb;

				state = LONG_OPT_WHAT;
			}
			else
			{
				goto apply_args_error;
			}
		}
		else if (state == LONG_OPT_WHAT)
		{
			if (opt->opt_t != A_PMN)
				goto apply_args_error;

			char *slashp = index(s, '/');

			if (slashp && slashp == nextword(s) && patch->p_diff == DEL)
			{
				wordCopy(argument, slashp + 1);

				dbg_cn(cn, DBGL_SYS, DBGT_ERR,
							 "--%s %s can not be resetted and refined at the same time. Just omit /%s!",
							 opt->long_name, patch->p_val, argument);

				goto apply_args_error;
			}
			else if (slashp && slashp == nextword(s))
			{
				//nextword starts with slashp

				s = slashp + 1;
				state = LONG_OPT_ARG;
			}
			else
			{
				if ((call_option(ADD, OPT_ADJUST, 0 /*save*/, opt, patch, pmn_s, cn)) == FAILURE)
					goto apply_args_error;

				//indicate end of LONG_OPT_ARGs
				if ((call_option(ADD, cmd, (on_the_fly ? YES : NO) /*save*/, opt, patch, pmn_s, cn)) == FAILURE)
					goto apply_args_error;

				del_opt_parent(&Patch_opt, patch);
				patch = NULL;
				state = NEXT_OPT;
			}
		}
		else if (state == LONG_OPT_ARG && wordlen(s) >= 1)
		{
			opt_arg = get_option(opt, NO, s);

			if (!opt_arg || opt_arg->opt_t != A_CS1 || opt_arg->order != opt->order)
				goto apply_args_error;

			equalp = index(s, '=');

			if (equalp && equalp < s + wordlen(s))
			{
				s = equalp + 1;
			}
			else
			{
				if ((s = nextword(s)) == NULL)
					goto apply_args_error;
			}

			state = LONG_OPT_ARG_VAL;
		}
		else if (state == LONG_OPT_ARG_VAL && wordlen(s) >= 1)
		{
			s = s + (del = ((s[0] == ARG_RESET_CHAR) ? 1 : 0));

			if ((pb = call_option(del, OPT_PATCH, 0 /*save*/, opt_arg, patch, s, cn)) == FAILURE)
				goto apply_args_error;

			s += pb;

			state = LONG_OPT_WHAT;
		}
		else
		{
			goto apply_args_error;
		}

		continue;
	}

	if (state != LONG_OPT_ARG && state != NEW_OPT && state != NEXT_OPT)
		goto apply_args_error;

	dbgf_all(0, DBGT_INFO, "all opts and args succesfully called with %s", opt_cmd2str[cmd]);

	if ((order = respect_opt_order(cmd, order, 99, NULL, Load_config, OPT_SET_POST, cn)) < 0)
		goto apply_args_error;

	return SUCCESS;

apply_args_error:

	if (patch)
		del_opt_parent(&Patch_opt, patch);

	snprintf(argument, MIN(sizeof(argument), wordlen(s) + 1), "%s", s);

	//otherwise invalid sysntax identified only by apply_stream_opts is not printed;
	dbg_cn(cn, DBGL_SYS, DBGT_ERR, "invalid argument: %s", argument);

	return FAILURE;
}

void apply_init_args(int argc, char *argv[])
{
	prog_name = argv[0];

	get_init_string(argc, argv);

	char *stream_opts = nextword(init_string);

	struct ctrl_node *cn = create_ctrl_node(STDOUT_FILENO, NULL, (getuid() | getgid()) /*are we root*/ ? NO : YES);

	if ((apply_stream_opts(stream_opts, ARG_DEV, OPT_CHECK, YES /*load cfg*/, cn) == FAILURE) ||
			(apply_stream_opts(stream_opts, ARG_DEV, OPT_APPLY, YES /*load cfg*/, cn) == FAILURE))
		cleanup_all(CLEANUP_FAILURE);

	respect_opt_order(OPT_APPLY, 0, 99, NULL, NO /*load_cofig*/, OPT_POST, 0 /*probably closed*/);

	close_ctrl_node(CTRL_CLOSE_STRAIGHT, cn);

	trigger_tun_update();

	free_init_string();
}

char *ipStr(uint32_t addr)
{
#define IP2S_ARRAY_LEN 10
	static uint8_t c = 0;
	static char str[IP2S_ARRAY_LEN][ADDR_STR_LEN];

	prof_start(PROF_ipStr);

	c = (c + 1) % IP2S_ARRAY_LEN;

	inet_ntop(AF_INET, &addr, str[c], ADDR_STR_LEN);

	prof_stop(PROF_ipStr);
	return str[c];
}

int8_t str2netw(char *args, uint32_t *ip, char delimiter, struct ctrl_node *cn, int32_t *val, int32_t max)
{
	struct in_addr tmp_ip_holder;
	char *slashptr = NULL;

	char switch_arg[30];

	if (wordlen(args) < 1 || wordlen(args) > 29)
		return FAILURE;

	wordCopy(switch_arg, args);
	switch_arg[wordlen(args)] = '\0';

	if (val)
	{
		if ((slashptr = strchr(switch_arg, delimiter)) != NULL)
		{
			char *end = NULL;

			*slashptr = '\0';

			errno = 0;
			*val = strtol(slashptr + 1, &end, 10);

			if ((errno == ERANGE) || *val > max || *val < 0)
			{
				dbgf_cn(cn, DBGL_SYS, DBGT_ERR, "invalid argument %s %s",
								args, strerror(errno));

				return FAILURE;
			}
			else if (end == slashptr + 1 || wordlen(end))
			{
				dbgf_cn(cn, DBGL_SYS, DBGT_ERR, "invalid argument trailer %s", end);
				return FAILURE;
			}
		}
		else
		{
			dbgf_cn(cn, DBGL_SYS, DBGT_ERR, "invalid argument %s! Fix you parameters!", switch_arg);
			return FAILURE;
		}
	}

	errno = 0;

	if ((inet_pton(AF_INET, switch_arg, &tmp_ip_holder)) < 1 || !tmp_ip_holder.s_addr)
	{
		dbgf_all(0, DBGT_WARN, "invalid argument: %s: %s", args, strerror(errno));
		return FAILURE;
	}

	*ip = tmp_ip_holder.s_addr;

	return SUCCESS;
}

void addr_to_str(uint32_t addr, char *str)
{
	inet_ntop(AF_INET, &addr, str, ADDR_STR_LEN);
	return;
}

uint32_t validate_net_mask(uint32_t ip, uint32_t mask, struct ctrl_node *cn)
{
	uint32_t nip = ip & htonl(0xFFFFFFFF << (32 - mask));

	if (cn && nip != ip)
		dbg_cn(cn, DBGL_CHANGES, DBGT_WARN,
					 "inconsistent network prefix %s/%d - probably you mean: %s/%d",
					 ipStr(ip), mask, ipStr(nip), mask);

	return nip;
}

int32_t check_file(char *path, uint8_t write, uint8_t exec)
{
	struct stat fstat;

	errno = 0;
	int stat_ret = stat(path, &fstat);

	if (stat_ret < 0)
	{
		dbgf(DBGL_CHANGES, DBGT_WARN, "%s does not exist! (%s)",
				 path, strerror(errno));
	}
	else
	{
		if (S_ISREG(fstat.st_mode) &&
				(S_IRUSR & fstat.st_mode) &&
				((S_IWUSR & fstat.st_mode) || !write) &&
				((S_IXUSR & fstat.st_mode) || !exec))
			return SUCCESS;

		dbgf(DBGL_SYS, DBGT_ERR,
				 "%s exists but has inapropriate permissions (%s)",
				 path, strerror(errno));
	}

	return FAILURE;
}

int32_t check_dir(char *path, uint8_t create, uint8_t write)
{
	struct stat fstat;

	errno = 0;
	int stat_ret = stat(path, &fstat);

	if (stat_ret < 0)
	{
		if (create && mkdir(path, S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) >= 0)
			return SUCCESS;

		dbgf(DBGL_SYS, DBGT_ERR,
				 "directory %s does not exist and can not be created (%s)", path, strerror(errno));
	}
	else
	{
		if (S_ISDIR(fstat.st_mode) &&
				(S_IRUSR & fstat.st_mode) &&
				(S_IXUSR & fstat.st_mode) &&
				((S_IWUSR & fstat.st_mode) || !write))
			return SUCCESS;

		dbgf(DBGL_SYS, DBGT_ERR,
				 "directory %s exists but has inapropriate permissions (%s)", path, strerror(errno));
	}

	return FAILURE;
}

uint32_t wordlen(char *s)
{
	uint32_t i = 0;

	if (!s)
		return 0;

	for (i = 0; i < strlen(s); i++)
	{
		if (s[i] == '\0' || s[i] == '\n' || s[i] == ' ' || s[i] == '\t')
			return i;
	}

	return i;
}

int8_t wordsEqual(char *a, char *b)
{
	if (wordlen(a) == wordlen(b) && !strncmp(a, b, wordlen(a)))
		return YES;

	return NO;
}

void wordCopy(char *out, char *in)
{
	if (out && in && wordlen(in) < MAX_ARG_SIZE)
	{
		snprintf(out, wordlen(in) + 1, "%s", in);
	}
	else if (out && !in)
	{
		out[0] = 0;
	}
	else
	{
		dbgf(DBGL_SYS, DBGT_ERR, "called with out: %s  and  in: %s", out, in);
		cleanup_all(-500017);
	}
}

static int8_t show_info(struct ctrl_node *cn, void *data, struct opt_type *opt, struct opt_parent *p, struct opt_child *c)
{
	if (c)
		dbg_printf(cn, "    /%-18s %-20s %s%s\n",
							 c->c_opt->long_name, c->c_val, (c->c_ref ? "resolved from " : ""), (c->c_ref ? c->c_ref : ""));
	else
		dbg_printf(cn, " %-22s %-20s %s%s\n",
							 opt->long_name, p->p_val, (p->p_ref ? "resolved from " : ""), (p->p_ref ? p->p_ref : ""));

	return SUCCESS;
}

static int32_t opt_show_info(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
	{
		/*
		//TBD: include all routing tables
		dbg_printf(cn, " source_version %s\n", SOURCE_VERSION);
		dbg_printf(cn, " compat_version %i\n", COMPAT_VERSION);
		dbg_printf(cn, "\n");
		*/

		func_for_each_opt(cn, NULL, "opt_show_info()", show_info);

		if (!on_the_fly)
			cleanup_all(CLEANUP_SUCCESS);
	}

	return SUCCESS;
}

static int32_t opt_no_fork(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
	{
		debug_level = strtol(patch->p_val, NULL, 10);

		activate_debug_system();
	}
	else if (cmd == OPT_POST && !on_the_fly)
	{
		activate_debug_system();
	}

	return SUCCESS;
}

static int32_t opt_debug(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
	{
		int ival = strtol(patch->p_val, NULL, 10);

		if (ival == DBGL_SYS ||
				ival == DBGL_CHANGES ||
				ival == DBGL_TEST ||
				ival == DBGL_ALL)
		{
			remove_dbgl_node(cn);
			add_dbgl_node(cn, ival);
			return SUCCESS;
		}
		else if (ival == DBGL_ROUTES)
		{
			check_apply_parent_option(ADD, OPT_APPLY, _save, get_option(0, 0, ARG_ROUTES), 0, cn);
		}
		else if (ival == DBGL_LINKS)
		{
			check_apply_parent_option(ADD, OPT_APPLY, _save, get_option(0, 0, ARG_LINKS), 0, cn);
		}
		else if (ival == DBGL_DETAILS)
		{
			check_apply_parent_option(ADD, OPT_APPLY, 0, get_option(0, 0, ARG_STATUS), 0, cn);
			check_apply_parent_option(ADD, OPT_APPLY, _save, get_option(0, 0, ARG_LINKS), 0, cn);
			check_apply_parent_option(ADD, OPT_APPLY, _save, get_option(0, 0, ARG_ORIGINATORS), 0, cn);
		}
		else if (ival == DBGL_GATEWAYS)
		{
			check_apply_parent_option(ADD, OPT_APPLY, _save, get_option(0, 0, ARG_GATEWAYS), 0, cn);
		}
		else if (ival == DBGL_PROFILE)
		{
#if defined MEMORY_USAGE
			debugMemory(cn);
#endif
#if defined PROFILE_DATA
			prof_print(cn);
#endif
		}
		close_ctrl_node(CTRL_CLOSE_SUCCESS, cn);
	}

	return SUCCESS;
}

static int32_t opt_help(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd != OPT_APPLY)
		return SUCCESS;

	if (!cn)
		return FAILURE;

	if (!strcmp(opt->long_name, ARG_HELP))
	{
		show_opts_help(cn);
	}
	else if (!strcmp(opt->long_name, ARG_VERSION))
	{
		dbg_printf(cn, "BMX %s%s (compatibility version %i)\n",
							 SOURCE_VERSION, (strncmp(REVISION_VERSION, "0", 1) != 0 ? REVISION_VERSION : ""), COMPAT_VERSION);
	}
	else
	{
		show_opts_help(cn);
	}

	if (!on_the_fly)
		cleanup_all(CLEANUP_SUCCESS);

	return SUCCESS;
}

static int32_t opt_quit(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
		close_ctrl_node(CTRL_CLOSE_SUCCESS, cn);

	return SUCCESS;
}

static int32_t opt_run_dir(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	char tmp_dir[MAX_PATH_SIZE] = "";

	if (cmd == OPT_CHECK || cmd == OPT_APPLY)
	{
		if (wordlen(patch->p_val) + 1 >= MAX_PATH_SIZE || patch->p_val[0] != '/')
			return FAILURE;

		snprintf(tmp_dir, wordlen(patch->p_val) + 1, "%s", patch->p_val);

		if (check_dir(tmp_dir, YES /*create*/, YES /*writable*/) == FAILURE)
			return FAILURE;

		if (cmd == OPT_APPLY)
		{
			strcpy(run_dir, tmp_dir);
		}
	}
	else if (cmd == OPT_SET_POST && !on_the_fly)
	{
		if (check_dir(run_dir, YES /*create*/, YES /*writable*/) == FAILURE)
			return FAILURE;
	}

	return SUCCESS;
}

static struct opt_type control_options[] =
		{
				//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help
				{ODI, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				 0, "\nGeneral configuration options:"},

				{ODI, 0, 0, ARG_HELP, 'h', A_PS0, A_USR, A_DYI, A_ARG, A_END, 0, 0, 0, 0, opt_help,
				 0, "help"},

				{ODI, 0, 0, ARG_VERSION, 'v', A_PS0, A_USR, A_DYI, A_ARG, A_ANY, 0, 0, 0, 0, opt_help,
				 0, "show version"},

				{ODI, 0, 0, ARG_TEST, 0, A_PS0, A_ADM, A_DYI, A_ARG, A_ANY, &Testing, 0, 1, 0, 0,
				 0, "test remaining args and provide feedback about projected success (without applying them)"},

				{ODI, 0, 0, ARG_NO_FORK, 'd', A_PS1, A_ADM, A_INI, A_ARG, A_ANY, 0, DBGL_MIN, DBGL_MAX, -1, opt_no_fork,
				 ARG_VALUE_FORM, "print debug information instead of forking to background\n"},
				{ODI, 0, 0, ARG_DEBUG, 'd', A_PS1, A_ADM, A_DYN, A_ARG, A_ETE, 0, DBGL_MIN, DBGL_MAX, -1, opt_debug,
				 ARG_VALUE_FORM, "show debug information:\n"
												 "	 0  : system\n"
												 "	 1  : originators\n"
												 "	 2  : gateways\n"
												 "	 3  : changes\n"
												 "	 4  : verbose changes\n"
												 "	 5  : profiling (depends on -DDEBUG_MALLOC -DMEMORY_USAGE -DPROFILE_DATA)\n"
												 "	 8  : details\n"
												 "	 9  : announced networks and interfaces\n"
												 "	10  : links\n"
												 "	11  : testing"},

				{ODI, 2, 0, ARG_RUN_DIR, 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, 0, 0, 0, 0, opt_run_dir,
				 ARG_DIR_FORM, "set runtime DIR of pid, socket,... - default: " DEF_RUN_DIR " (must be defined before --" ARG_CONNECT ")."},

				{ODI, 3, 0, "loop_mode", 'l', A_PS0, A_ADM, A_INI, A_ARG, A_ANY, &loop_mode, 0, 1, 0, 0,
				 0, "put client daemon in loop mode to periodically refresh debug information"},

				{ODI, 3, 0, ARG_CONNECT, 'c', A_PS0, A_ADM, A_INI, A_ARG, A_EAT, 0, 0, 0, 0, opt_connect,
				 0, "set client mode. Connect and forward remaining args to main routing daemon"},

				//order=5: so when used during startup it also shows the config-file options
				{ODI, 5, 0, ARG_SHOW_CHANGED, 'i', A_PS0, A_ADM, A_DYI, A_ARG, A_ANY, 0, 0, 0, 0, opt_show_info,
				 0, "inform about configured options"},

				{ODI, 5, 0, "dbg_mute_timeout", 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &dbg_mute_to, 0, 10000000, 100000, 0,
				 ARG_VALUE_FORM, "set timeout in ms for muting frequent messages"},

				{ODI, 5, 0, ARG_QUIT, EOS_DELIMITER, A_PS0, A_USR, A_DYN, A_ARG, A_END, 0, 0, 0, 0, opt_quit, 0, 0}};

void init_control(void)
{
	int i;

	for (i = DBGL_MIN; i <= DBGL_MAX; i++)
	{
		OLInitializeListHead(&dbgl_clients[i]);
	}

	OLInitializeListHead(&ctrl_list);
	OLInitializeListHead(&opt_list);

	openlog("bmx", LOG_PID, LOG_DAEMON);

	memset(&Patch_opt, 0, sizeof(struct opt_type));
	OLInitializeListHead(&Patch_opt.d.list);
	OLInitializeListHead(&Patch_opt.d.childs_type_list);
	OLInitializeListHead(&Patch_opt.d.parents_instance_list);

	register_options_array(control_options, sizeof(control_options));
}

void cleanup_config(void)
{
	del_opt_parent(&Patch_opt, NULL);

	while (!OLIsListEmpty(&opt_list))
		remove_option((struct opt_type *)OLGetNext(&opt_list));

	free_init_string();
}

void cleanup_control(void)
{
	int8_t i;

	debug_system_active = NO;
	closelog();

	if (unix_sock)
		close(unix_sock);

	unix_sock = 0;

	//remove all cn (ctrl_node) from client lists

	for (i = DBGL_MIN; i <= DBGL_MAX; i++)
	{
		while (!OLIsListEmpty(&dbgl_clients[i]))
		{
			debugFree(OLRemoveHeadList(&dbgl_clients[i]), 218);
		}
	}

	//free cn after clearing dbgl_clients
	close_ctrl_node(CTRL_PURGE_ALL, 0);
}
