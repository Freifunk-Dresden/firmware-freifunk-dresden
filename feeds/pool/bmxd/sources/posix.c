/*
 * Copyright (C) 2006 BATMAN contributors:
 * Thomas Lopatic, Marek Lindner, Axel Neumann
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
#include <arpa/inet.h>
#include <stdio.h>
#include <errno.h>
#include <sys/types.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "batman.h"
#include "os.h"
#include "originator.h"
#include "metrics.h"
#include "plugin.h"
#include "schedule.h"
#include "tunnel.h"

static int8_t stop = 0;

//static clock_t start_time;
static struct timeval start_time_tv;
static struct timeval ret_tv, new_tv, diff_tv, acceptable_m_tv, acceptable_p_tv, max_tv = {0, (2000 * MAX_SELECT_TIMEOUT_MS)};

/* get_time functions MUST be called at least every 2*MAX_SELECT_TIMEOUT_MS to allow for properly working time-drift checks */

/* overlaps after approximately 138 years */
//#define get_time_sec()  get_time( NO, NULL  )

/* overlaps after 49 days, 17 hours, 2 minutes, and 48 seconds */
//#define get_time_msec() get_time( YES, NULL )

void update_batman_time(struct timeval *precise_tv)
{
	timeradd(&max_tv, &new_tv, &acceptable_p_tv);
	timercpy(&acceptable_m_tv, &new_tv);
	gettimeofday(&new_tv, NULL);

	if (timercmp(&new_tv, &acceptable_p_tv, >)) // cppcheck-suppress syntaxError
	{
		timersub(&new_tv, &acceptable_p_tv, &diff_tv);
		timeradd(&start_time_tv, &diff_tv, &start_time_tv);
	}
	else if (timercmp(&new_tv, &acceptable_m_tv, <))
	{
		timersub(&acceptable_m_tv, &new_tv, &diff_tv);
		timersub(&start_time_tv, &diff_tv, &start_time_tv);
	}

	timersub(&new_tv, &start_time_tv, &ret_tv);

	if (precise_tv)
	{
		precise_tv->tv_sec = ret_tv.tv_sec;
		precise_tv->tv_usec = ret_tv.tv_usec;
	}

	batman_time = ((ret_tv.tv_sec * 1000) + (ret_tv.tv_usec / 1000));
	batman_time_sec = ret_tv.tv_sec;

#ifdef BATMAN_TIME_START
	batman_time += (BATMAN_TIME_START * (batman_time_t)1000);
	batman_time_sec += BATMAN_TIME_START;
#endif
}

char *get_human_uptime(uint32_t reference, int more)
{
	//                  DD:HH:MM:SS
	static char ut[256] = "00:00:00:00";

	if (more)
	{
		sprintf(ut, "%2i:%i%i:%i%i:%i%i",
						(int)(((batman_time_sec - reference) / 86400)),
						(int)(((batman_time_sec - reference) % 86400) / 36000) % 10,
						(int)(((batman_time_sec - reference) % 86400) / 3600) % 10,
						(int)(((batman_time_sec - reference) % 3600) / 600) % 10,
						(int)(((batman_time_sec - reference) % 3600) / 60) % 10,
						(int)(((batman_time_sec - reference) % 60) / 10) % 10,
						(int)(((batman_time_sec - reference) % 60)) % 10);
	}
	else
	{
		sprintf(ut, "%2i:%i%i:%i%i:%i%i",
						(int)(((batman_time_sec - reference) / 86400)),
						(int)(((batman_time_sec - reference) % 86400) / 36000) % 10,
						(int)(((batman_time_sec - reference) % 86400) / 3600) % 10,
						(int)(((batman_time_sec - reference) % 3600) / 600) % 10,
						(int)(((batman_time_sec - reference) % 3600) / 60) % 10,
						(int)(((batman_time_sec - reference) % 60) / 10) % 10,
						(int)(((batman_time_sec - reference) % 60)) % 10);
	}

	return ut;
}

void bat_wait(uint32_t sec, uint32_t msec)
{
	struct timeval time;

	//no debugging here because this is called from debug_output() -> dbg_fprintf() which may case a loop!
	//dbgf_all( DBGT_INFO, "%d sec %d msec...", sec, msec );

	time.tv_sec = sec + (msec / 1000);
	time.tv_usec = (msec * 1000) % 1000000;

	select(0, NULL, NULL, NULL, &time);

	//update_batman_time( NULL ); //this will cause critical system time drift message from the client
	//dbgf_all( DBGT_INFO, "bat_wait(): done");
}

int32_t rand_num(uint32_t limit)
{
	return (limit == 0 ? 0 : rand() % limit);
}

int8_t is_aborted()
{
	return stop != 0;
}

static void handler(int32_t sig)
{
	if (!Client_mode)
	{
		dbgf(DBGL_SYS, DBGT_ERR, "called with signal %d", sig);
	}

	printf("\n"); // to have a newline after ^C

	stop = 1;
}

/* counting bits based on http://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetTable */

static unsigned char BitsSetTable256[256];

static void init_set_bits_table256(void)
{
	BitsSetTable256[0] = 0;

	for (int i = 0; i < 256; i++)
	{
		BitsSetTable256[i] = (i & 1) + BitsSetTable256[i / 2];
	}
}

// count the number of true bits in v
uint8_t get_set_bits(uint32_t v)
{
	uint8_t c = 0;

	for (; v; v = v >> 8)
		c += BitsSetTable256[v & 0xff];

	return c;
}

int8_t send_udp_packet(unsigned char *packet_buff, int32_t packet_buff_len, struct sockaddr_in *dst, int32_t send_sock)
{
	int status = 0;

	dbgf_all(2, DBGT_INFO, "len %d", packet_buff_len);

	if (send_sock == 0)
		return 0;

	/*
	static struct iovec iov;
	iov.iov_base = packet_buff;
	iov.iov_len  = packet_buff_len;

	static struct msghdr m = { 0, sizeof( struct sockaddr_in ), &iov, 1, NULL, 0, 0 };
	m.msg_name = dst;

	status = sendmsg( send_sock, &m, 0 );
	*/

	status = sendto(send_sock, packet_buff, packet_buff_len, 0, (struct sockaddr *)dst, sizeof(struct sockaddr_in));

	if (status < 0)
	{
		if (errno == 1)
		{
			dbg_mute(2, 60, DBGL_SYS, DBGT_ERR,
							 "can't send udp packet: %s. Does your firewall allow outgoing packets on port %i ?",
							 strerror(errno), ntohs(dst->sin_port));
		}
		else
		{
			dbg_mute(2, 60, DBGL_SYS, DBGT_ERR, "can't send udp packet via fd %d: %s", send_sock, strerror(errno));
		}

		return -1;
	}

	return 0;
}

void cleanup_all(int status)
{
	static int cleaning_up = NO;

	if (status < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "Terminating with error code %d ! Please notify a developer", status);

		dbg(DBGL_SYS, DBGT_ERR, "raising SIGSEGV to simplify debugging ...");

		errno = 0;
		if (raise(SIGSEGV))
		{
			dbg(DBGL_SYS, DBGT_ERR, "raising SIGSEGV failed: %s...", strerror(errno));
		}
	}

	if (!cleaning_up)
	{
		cleaning_up = YES;

		// first, restore defaults...

		stop = 1;

		cleanup_schedule();

		purge_orig(0, NULL); // cleanup_all()

		tun_cleanup();

		cleanup_config(); //cleanup_init()
		cleanup_route();
		cleanup_originator();

		//clear/remove all interfaces
		OLForEach(bif, struct batman_if, if_list)
		{

			if (bif->if_active)
			{
				if_deactivate(bif);
			}

			remove_outstanding_ogms(bif);

			LIST_ENTRY *prev = OLGetPrev(bif);
			OLRemoveEntry(bif);

			//debugFree(bif->own_ogm_out, 1209);
			debugFree(bif, 1214);
			bif = (struct batman_if *)prev;
		}

		// last, close debugging system and check for forgotten resources...
		cleanup_control();

		checkLeak();
	}

	if (status == CLEANUP_SUCCESS)
	{
		exit(EXIT_SUCCESS);
	}
	else if (status == CLEANUP_FAILURE)
	{
		exit(EXIT_FAILURE);
	}
	else if (status == CLEANUP_RETURN)
	{
		return;
	}

	exit(EXIT_FAILURE);
}

int main(int argc, char *argv[])
{
	gettimeofday(&start_time_tv, NULL);
	gettimeofday(&new_tv, NULL);

	update_batman_time(NULL);

	My_pid = getpid();

	srand(My_pid);

	init_set_bits_table256();

	signal(SIGINT, handler);
	signal(SIGTERM, handler);
	signal(SIGPIPE, SIG_IGN);

	init_control();

	init_profile();

	init_route();

	init_route_args();

	init_originator();

	init_schedule();

	init_tunnel(); // uses tasks. must come after init_schedule()

	init_plugin();

	apply_init_args(argc, argv);

	check_kernel_config(NULL);

	start_schedule();

	batman();

	cleanup_all(CLEANUP_SUCCESS);

	return -1;
}
