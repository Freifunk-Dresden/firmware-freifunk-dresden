/*
 * Copyright (c) 2010  Axel Neumann
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
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdint.h>
#include <json/json.h>
//#include <dirent.h>
//#include <sys/inotify.h>

#include "bmx.h"
#include "msg.h"
#include "plugin.h"
#include "schedule.h"
#include "tools.h"
#include "json.h"
#include "ip.h"


#define CODE_CATEGORY_NAME "json"

static int32_t json_update_interval = DEF_JSON_UPDATE;
static int32_t current_update_interval = 0;

static char *json_dir = NULL;
static char *json_desc_dir = NULL;
static char *json_orig_dir = NULL;


STATIC_FUNC
json_object * fields_dbg_json(uint8_t relevance, uint8_t force_array, uint16_t data_size, uint8_t *data,
                    uint16_t min_msg_size, const struct field_format *format)
{
        TRACE_FUNCTION_CALL;
        assertion(-501300, (format && data));

        uint32_t msgs_size = 0;
        uint32_t columns = field_format_get_items(format);

        struct field_iterator it = {.format = format, .data = data, .data_size = data_size, .min_msg_size = min_msg_size};

        json_object *jfields = NULL;
        json_object *jarray = NULL;

        while ((msgs_size = field_iterate(&it)) == SUCCESS) {

                assertion(-501301, IMPLIES(it.field == 0, !jfields));
/*
                if (it.field == 0 && jfields) {
                        jarray = jarray ? jarray : json_object_new_array();
                        json_object_array_add(jarray, jfields);
                        jfields = NULL;
                }
*/

                if (format[it.field].field_relevance >= relevance) {

                        json_object *jfield_val;

                        if (format[it.field].field_type == FIELD_TYPE_UINT && it.field_bits <= 32) {
                                jfield_val = json_object_new_int(
                                        field_get_value(&format[it.field], min_msg_size, data, it.field_bit_pos, it.field_bits));
                        } else {
                                jfield_val = json_object_new_string(
                                        field_dbg_value(&format[it.field], min_msg_size, data, it.field_bit_pos, it.field_bits));
                        }

                        jfields = jfields ? jfields : json_object_new_object();

                        json_object_object_add(jfields, format[it.field].field_name, jfield_val);
                }

                if (force_array && it.field == (columns - 1)) {
                        jarray = jarray ? jarray : json_object_new_array();
                        json_object_array_add(jarray, jfields);
                        jfields = NULL;
                }

        }

        assertion(-501302, (data_size ? msgs_size == data_size : msgs_size == min_msg_size));

        return jarray ? jarray : jfields;

/*
        if (jfields && (force_array || jarray)) {
                jarray = jarray ? jarray : json_object_new_array();
                json_object_array_add(jarray, jfields);
                return jarray;
        }

        return jfields;
*/
}




STATIC_FUNC
int32_t update_json_options(IDM_T show_options, IDM_T show_parameters, char *file_name)
{
        assertion(-501271, (json_dir));

        int fd;
        char path_name[MAX_PATH_SIZE + 20] = "";

        sprintf(path_name, "%s/%s", json_dir, file_name);

        if ((fd = open(path_name, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)) < 0) { //check permissions of generated file

		dbgf_sys(DBGT_ERR, "could not open %s - %s", path_name, strerror(errno) );
		return FAILURE;
	}


        struct opt_type * p_opt = NULL;
        json_object *jopts = json_object_new_array();

        while ((p_opt = list_iterate(&opt_list, p_opt))) {

                if ((!show_options && !p_opt->d.parents_instance_list.items) || p_opt->parent_name)
                        continue;

                assertion(-501303, (p_opt->name));

                json_object *jopt = json_object_new_object();

                json_object *jopt_name = json_object_new_string(p_opt->name);
                json_object_object_add(jopt, "name", jopt_name);

                if (show_options) {

                        json_object *jopt_relevance = json_object_new_int(p_opt->relevance);
                        json_object_object_add(jopt, "relevance", jopt_relevance);

                        json_object *jopt_configurable = json_object_new_int(p_opt->cfg_t == A_CFA);
                        json_object_object_add(jopt, "configurable", jopt_configurable);

                        json_object *jopt_dynamic = json_object_new_int(p_opt->dyn_t == A_DYN || p_opt->dyn_t == A_DYI);
                        json_object_object_add(jopt, "dynamic", jopt_dynamic);

                        json_object *jopt_multi = json_object_new_int(p_opt->opt_t == A_PM1N);
                        json_object_object_add(jopt, "multioption", jopt_multi);


                        if (p_opt->opt_t != A_PS0 && p_opt->imin != p_opt->imax) {

                                json_object *jopt_min = json_object_new_int(p_opt->imin);
                                json_object_object_add(jopt, "min", jopt_min);
                                json_object *jopt_max = json_object_new_int(p_opt->imax);
                                json_object_object_add(jopt, "max", jopt_max);
                                json_object *jopt_def = json_object_new_int(p_opt->idef);
                                json_object_object_add(jopt, "def", jopt_def);

                        } else if (p_opt->sdef) {

                                json_object *jopt_def = json_object_new_string(p_opt->sdef);
                                json_object_object_add(jopt, "def", jopt_def);
                        }

                        if (p_opt->syntax) {
                                json_object *jopt_syntax = json_object_new_string(p_opt->syntax);
                                json_object_object_add(jopt, "syntax", jopt_syntax);
                        }

                        if (p_opt->help) {
                                json_object *jopt_help = json_object_new_string(p_opt->help);
                                json_object_object_add(jopt, "help", jopt_help);
                        }

                        if (p_opt->d.childs_type_list.items) {
                                struct opt_type *c_opt = NULL;
                                json_object *jchilds = json_object_new_array();

                                while ((c_opt = list_iterate(&p_opt->d.childs_type_list, c_opt))) {

                                        assertion(-501304, (c_opt->parent_name && c_opt->name));

                                        json_object *jchild = json_object_new_object();

                                        json_object *jopt_name = json_object_new_string(c_opt->name);
                                        json_object_object_add(jchild, "name", jopt_name);

                                        if (c_opt->imin != c_opt->imax) {

                                                json_object *jopt_min = json_object_new_int(c_opt->imin);
                                                json_object_object_add(jchild, "min", jopt_min);
                                                json_object *jopt_max = json_object_new_int(c_opt->imax);
                                                json_object_object_add(jchild, "max", jopt_max);
                                                json_object *jopt_def = json_object_new_int(c_opt->idef);
                                                json_object_object_add(jchild, "def", jopt_def);

                                        } else if (c_opt->sdef) {

                                                json_object *jopt_def = json_object_new_string(c_opt->sdef);
                                                json_object_object_add(jchild, "def", jopt_def);
                                        }

                                        if (c_opt->syntax) {
                                                json_object *jopt_syntax = json_object_new_string(c_opt->syntax);
                                                json_object_object_add(jchild, "syntax", jopt_syntax);
                                        }

                                        if (c_opt->help) {
                                                json_object *jopt_help = json_object_new_string(c_opt->help);
                                                json_object_object_add(jchild, "help", jopt_help);
                                        }

                                        json_object_array_add(jchilds, jchild);
                                }
                                json_object_object_add(jopt, "CHILD_OPTIONS", jchilds);
                        }
                }

                if (show_parameters && p_opt->d.parents_instance_list.items) {

                        struct opt_parent *p = NULL;
                        json_object *jps = json_object_new_array();

                        while ((p = list_iterate(&p_opt->d.parents_instance_list, p))) {

                                assertion(-501305, (p_opt->name && p_opt->cfg_t != A_ARG));
                                json_object *jp = json_object_new_object();

                                json_object *jp_val = json_object_new_string(p->val);
                                json_object_object_add(jp, "value", jp_val);

                                if (p->ref) {
                                        json_object *jp_from = json_object_new_string(p->ref);
                                        json_object_object_add(jp, "from", jp_from);
                                }

                                if (p->childs_instance_list.items) {

                                        struct opt_child *c = NULL;
                                        json_object *jcs = json_object_new_array();

                                        while ((c = list_iterate(&p->childs_instance_list, c))) {

                                                json_object *jc = json_object_new_object();

                                                json_object *jc_name = json_object_new_string(c->opt->name);
                                                json_object_object_add(jc, "name", jc_name);

                                                json_object *jc_val = json_object_new_string(c->val);
                                                json_object_object_add(jc, "value", jc_val);

                                                if (c->ref) {
                                                        json_object *jc_from = json_object_new_string(c->ref);
                                                        json_object_object_add(jp, "from", jc_from);
                                                }
                                                json_object_array_add(jcs, jc);
                                        }
                                        json_object_object_add(jp, "CHILD_INSTANCES", jcs);
                                }
                                json_object_array_add(jps, jp);
                        }
                        json_object_object_add(jopt, "INSTANCES", jps);
                }
                json_object_array_add(jopts, jopt);
        }

        json_object * jobj = json_object_new_object();

        json_object_object_add(jobj, "OPTIONS", jopts);

        dprintf(fd, "%s\n", json_object_to_json_string(jobj));

        json_object_put(jobj);
        close(fd);
 	return SUCCESS;
}









STATIC_FUNC
void json_dev_event_hook(int32_t cb_id, void* data)
{

        if (!json_update_interval || terminating)
                return;

        TRACE_FUNCTION_CALL;

        int fd;
        char path_name[MAX_PATH_SIZE + 20] = "";
        sprintf(path_name, "%s/%s", json_dir, ARG_INTERFACES);

        if ((fd = open(path_name, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)) < 0) {

                dbgf_sys(DBGT_ERR, "could not open %s - %s", path_name, strerror(errno));

        } else {

                struct ctrl_node *cn = create_ctrl_node(fd, NULL, YES/*we are root*/);

                check_apply_parent_option(ADD, OPT_APPLY, 0, get_option(0, 0, ARG_JSON_STATUS), ARG_INTERFACES, cn);

                close_ctrl_node(CTRL_CLOSE_STRAIGHT, cn);
        }
}

STATIC_FUNC
void json_config_event_hook(int32_t cb_id, void *data)
{
        if (!json_update_interval || terminating)
                return;

        TRACE_FUNCTION_CALL;

        update_json_options(0, 1, JSON_PARAMETERS_FILE);

        json_dev_event_hook(cb_id, data);
}

STATIC_FUNC
void json_status_event_hook(int32_t cb_id, void* data)
{
        if (!json_update_interval || terminating)
                return;

        TRACE_FUNCTION_CALL;

        int fd;
        char path_name[MAX_PATH_SIZE + 20] = "";
        sprintf(path_name, "%s/%s", json_dir, ARG_STATUS);

        if ((fd = open(path_name, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)) < 0) {

                dbgf_sys(DBGT_ERR, "could not open %s - %s", path_name, strerror(errno));

        } else {

                struct ctrl_node *cn = create_ctrl_node(fd, NULL, YES/*we are root*/);

                check_apply_parent_option(ADD, OPT_APPLY, 0, get_option(0, 0, ARG_JSON_STATUS), ARG_STATUS, cn);

                close_ctrl_node(CTRL_CLOSE_STRAIGHT, cn);
        }
}

STATIC_FUNC
void json_links_event_hook(int32_t cb_id, void* data)
{
        if (!json_update_interval || terminating)
                return;

        TRACE_FUNCTION_CALL;

        int fd;
        char path_name[MAX_PATH_SIZE + 20] = "";
        sprintf(path_name, "%s/%s", json_dir, ARG_LINKS);

        if ((fd = open(path_name, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)) < 0) {

                dbgf_sys(DBGT_ERR, "could not open %s - %s", path_name, strerror(errno));

        } else {

                struct ctrl_node *cn = create_ctrl_node(fd, NULL, YES/*we are root*/);

                check_apply_parent_option(ADD, OPT_APPLY, 0, get_option(0, 0, ARG_JSON_STATUS), ARG_LINKS, cn);

                close_ctrl_node(CTRL_CLOSE_STRAIGHT, cn);
        }
}

STATIC_FUNC
void json_originator_event_hook(int32_t cb_id, struct orig_node *orig)
{
        TRACE_FUNCTION_CALL;

        assertion(-501272, (json_orig_dir));
        assertion(-501347, (cb_id == PLUGIN_CB_DESCRIPTION_DESTROY || cb_id == PLUGIN_CB_DESCRIPTION_CREATED));

        struct orig_node *on;
        char path_name[MAX_PATH_SIZE];
        int fd;

        if (cb_id == PLUGIN_CB_DESCRIPTION_DESTROY) {

                if ((on = orig)) {

                        sprintf(path_name, "%s/%s", json_orig_dir, globalIdAsString(&on->global_id));

                        if ((fd = open(path_name, O_RDONLY)) > 0 && close(fd) == 0) {
                                
                                dbgf_all(DBGT_INFO, "removing destroyed json-originator=%s", path_name);

                                if (remove(path_name) != 0) {
                                        dbgf_sys(DBGT_ERR, "could not remove %s: %s \n", path_name, strerror(errno));
                                }
                        }
                }
                return;

        } else {

                struct avl_node *it = NULL;
                while ((on = orig ? orig : avl_iterate_item(&orig_tree, &it))) {

                        sprintf(path_name, "%s/%s", json_orig_dir, globalIdAsString(&on->global_id));

                        if ((fd = open(path_name, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)) < 0) {

                                dbgf_sys(DBGT_ERR, "could not open %s - %s", path_name, strerror(errno));

                        } else {

                                struct ctrl_node *cn = create_ctrl_node(fd, NULL, YES/*we are root*/);

                                struct status_handl *handl = NULL;
                                uint32_t data_len;

                                char status_name[sizeof (((struct status_handl *) NULL)->status_name)] = ARG_ORIGINATORS;

                                if ((handl = avl_find_item(&status_tree, status_name)) &&
                                        (data_len = ((*(handl->frame_creator))(handl, on)))) {

                                        json_object *jdesc_fields = NULL;

                                        if ((jdesc_fields = fields_dbg_json(FIELD_RELEVANCE_HIGH, NO,
                                                data_len, handl->data, handl->min_msg_size, handl->format))) {

                                                dbg_printf(cn, "%s\n", json_object_to_json_string(jdesc_fields));
                                                json_object_put(jdesc_fields);

                                                dbgf_all(DBGT_INFO, "creating json-originator=%s", path_name);
                                        }
                                }

                                close_ctrl_node(CTRL_CLOSE_STRAIGHT, cn);
                        }

                        if (orig)
                                break;
                }
        }
}


STATIC_FUNC
void json_route_change_hook(uint8_t del, struct orig_node *on)
{
        json_originator_event_hook(del ? PLUGIN_CB_DESCRIPTION_DESTROY : PLUGIN_CB_DESCRIPTION_CREATED, on);
}

STATIC_FUNC
void json_description_event_hook(int32_t cb_id, struct orig_node *on)
{
        TRACE_FUNCTION_CALL;

        assertion(-501306, (on));
        assertion(-501270, IMPLIES(cb_id == PLUGIN_CB_DESCRIPTION_CREATED, (on && on->desc)));
        assertion(-501273, (cb_id == PLUGIN_CB_DESCRIPTION_DESTROY || cb_id == PLUGIN_CB_DESCRIPTION_CREATED));
        assertion(-501274, IMPLIES(initializing, cb_id == PLUGIN_CB_DESCRIPTION_CREATED));
        assertion(-501275, (json_desc_dir));

        dbgf_all(DBGT_INFO, "cb_id=%d", cb_id);

        int fd;
        char path_name[MAX_PATH_SIZE];
        sprintf(path_name, "%s/%s", json_desc_dir, globalIdAsString(&on->global_id));

        if (cb_id == PLUGIN_CB_DESCRIPTION_DESTROY) {

                if ((fd = open(path_name, O_RDONLY)) > 0 && close(fd) == 0) {

                        dbgf_all(DBGT_INFO, "removing destroyed json-description=%s", path_name);

                        if (remove(path_name) != 0) {
                                dbgf_sys(DBGT_ERR, "could not remove %s: %s \n", path_name, strerror(errno));
                        }
                }

        } else {

                if ((fd = open(path_name, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)) < 0) { //check permissions of generated file

                        dbgf_sys(DBGT_ERR, "could not open %s - %s", path_name, strerror(errno));
                        return;
                }

                json_object *jorig = json_object_new_object();

                json_object *jhash = json_object_new_string(memAsHexString(((char*) &(on->dhn->dhash)), sizeof (on->dhn->dhash)));
                
                json_object_object_add(jorig, "descSha", jhash);

                json_object *jblocked = json_object_new_int(on->blocked);
                json_object_object_add(jorig, "blocked", jblocked);

                uint16_t tlvs_len = ntohs(on->desc->extensionLen);
                struct msg_description_adv * desc_buff =
                        debugMalloc(sizeof (struct msg_description_adv) +tlvs_len, -300361);

                desc_buff->transmitterIID4x = htons(on->dhn->myIID4orig);
                memcpy(&desc_buff->desc, on->desc, sizeof (struct description) +tlvs_len);

                json_object *jdesc_fields = NULL;

                if ((jdesc_fields = fields_dbg_json(
                        FIELD_RELEVANCE_MEDI, NO, sizeof (struct msg_description_adv) +tlvs_len, (uint8_t*) desc_buff,
                        packet_frame_handler[FRAME_TYPE_DESC_ADV].min_msg_size,
                        packet_frame_handler[FRAME_TYPE_DESC_ADV].msg_format))) {

                        if (tlvs_len) {

                                struct rx_frame_iterator it = {
                                        .caller = __FUNCTION__, .on = on, .cn = NULL, .op = TLV_OP_PLUGIN_MIN,
                                        .handls = description_tlv_handl, .handl_max = BMX_DSC_TLV_MAX,
                                        .process_filter = FRAME_TYPE_PROCESS_ALL,
                                        .data = ((uint8_t*) on->desc), .frame_type = -1,
                                        .frames_in = (((uint8_t*) on->desc) + sizeof (struct description)),
                                        .frames_length = tlvs_len
                                };

                                json_object *jextensions = NULL;

                                while (rx_frame_iterate(&it) > TLV_RX_DATA_DONE) {

                                        json_object * jext_fields;

                                        if ((jext_fields = fields_dbg_json(
                                                FIELD_RELEVANCE_MEDI, YES, it.frame_msgs_length, it.msg,
                                                it.handl->min_msg_size, it.handl->msg_format))) {

                                                json_object *jext = json_object_new_object();
                                                json_object_object_add(jext, it.handl->name, jext_fields);

                                                jextensions = jextensions ? jextensions : json_object_new_array();

                                                json_object_array_add(jextensions, jext);
                                        }
                                }

                                if (jextensions)
                                        json_object_object_add(jdesc_fields, "extensions", jextensions);

                        }
                        json_object_object_add(jorig, packet_frame_handler[FRAME_TYPE_DESC_ADV].name, jdesc_fields);
                }

                dprintf(fd, "%s\n", json_object_to_json_string(jorig));

                dbgf_all(DBGT_INFO, "creating json-description=%s", path_name);

                json_object_put(jorig);
                debugFree(desc_buff, -300362);
                close(fd);
        }

        json_originator_event_hook(cb_id, on);
}






STATIC_FUNC
void update_json_status(void *data)
{
        assertion(-501276, (json_dir));
        assertion(-501307, (json_update_interval));

        task_register(json_update_interval, update_json_status, NULL, -300378);

        json_status_event_hook(0, NULL);
        json_dev_event_hook(0, NULL);
        json_links_event_hook(0, NULL);
        json_originator_event_hook(PLUGIN_CB_DESCRIPTION_CREATED, NULL);
}





STATIC_FUNC
int32_t opt_json_status(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
        TRACE_FUNCTION_CALL;

        if (cmd == OPT_CHECK || cmd == OPT_APPLY) {

                uint8_t relevance = DEF_RELEVANCE;
                struct opt_child *c = NULL;

                while ((c = list_iterate(&patch->childs_instance_list, c))) {

                        if (!strcmp(c->opt->name, ARG_RELEVANCE))
                                relevance = strtol(c->val, NULL, 10);
                }

                struct status_handl *handl = NULL;
                uint32_t data_len;
                char status_name[sizeof (((struct status_handl *) NULL)->status_name)] = {0};

                strncpy(status_name, patch->val, sizeof (status_name));

                if ((handl = avl_find_item(&status_tree, status_name))) {

                        if (cmd == OPT_APPLY && (data_len = ((*(handl->frame_creator))(handl, NULL)))) {

                                json_object *jorig = json_object_new_object();
                                json_object *jdesc_fields = NULL;

                                if ((jdesc_fields = fields_dbg_json(relevance, handl->multiline,
                                        data_len, handl->data, handl->min_msg_size, handl->format))) {

                                        json_object_object_add(jorig, handl->status_name, jdesc_fields);
                                }

                                const char * data = json_object_to_json_string(jorig);

                                if (cn)
                                        dbg_printf(cn, "%s\n", data);

                                json_object_put(jorig);

                        }

                } else {
                        return FAILURE;
                }
	}

	return SUCCESS;
}


STATIC_FUNC
int32_t opt_json_update_interval(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{

        // this function is used to initialize all json directories

        if (initializing && !json_dir && (cmd == OPT_CHECK || cmd == OPT_APPLY || cmd == OPT_SET_POST)) {

                static char tmp_json_dir[MAX_PATH_SIZE];
                static char tmp_desc_dir[MAX_PATH_SIZE];
                static char tmp_orig_dir[MAX_PATH_SIZE];

                assertion(-501277, (strlen(run_dir) > 3));

                sprintf(tmp_json_dir, "%s/%s", run_dir, DEF_JSON_SUBDIR);
                sprintf(tmp_orig_dir, "%s/%s", tmp_json_dir, DEF_JSON_ORIG_SUBDIR);
                sprintf(tmp_desc_dir, "%s/%s", tmp_json_dir, DEF_JSON_DESC_SUBDIR);

                if (check_dir(run_dir, YES/*create*/, YES/*writable*/) == FAILURE)
                        return FAILURE;

                if (check_dir(tmp_json_dir, YES/*create*/, YES/*writable*/) == FAILURE)
			return FAILURE;

                if (check_dir(tmp_orig_dir, YES/*create*/, YES/*writable*/) == FAILURE)
                        return FAILURE;

                if (check_dir(tmp_desc_dir, YES/*create*/, YES/*writable*/) == FAILURE)
                        return FAILURE;

                json_dir =  tmp_json_dir;
                json_orig_dir = tmp_orig_dir;
                json_desc_dir = tmp_desc_dir;

        }

        if (initializing && cmd == OPT_SET_POST) {

                assertion(-501308, (json_dir && json_orig_dir && json_desc_dir));

                if (rm_dir_content(json_orig_dir, NULL) == FAILURE)
                        return FAILURE;

                if (rm_dir_content(json_desc_dir, NULL) == FAILURE)
                        return FAILURE;

                update_json_options(1, 0, JSON_OPTIONS_FILE);
        }

        if (cmd == OPT_SET_POST && current_update_interval != json_update_interval) {

                if(current_update_interval) {
                        task_remove(update_json_status, NULL);
                        set_route_change_hooks(json_route_change_hook, DEL);
                }

                if (json_update_interval){
                        task_register(MAX(10, json_update_interval), update_json_status, NULL, -300379);
                        set_route_change_hooks(json_route_change_hook, ADD);
                }

                current_update_interval = json_update_interval;
        }

	return SUCCESS;
}


static struct opt_type json_options[]= {
//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help
	
	{ODI,0,ARG_JSON_UPDATE,		0,  9,2,A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&json_update_interval,	MIN_JSON_UPDATE,MAX_JSON_UPDATE,DEF_JSON_UPDATE,0,opt_json_update_interval,
                ARG_VALUE_FORM, "disable or periodically update json-status files every given milliseconds."}
        ,
	{ODI,0,ARG_JSON_STATUS,		0,  9,2,A_PS1N,A_USR,A_DYI,A_ARG,A_ANY,	0,		0, 		0,		0,0, 		opt_json_status,
			0,		"show status in json format\n"}
        ,
	{ODI,ARG_JSON_STATUS,ARG_RELEVANCE,'r',9,1,A_CS1,A_USR,A_DYI,A_ARG,A_ANY,0,	       MIN_RELEVANCE,   MAX_RELEVANCE,  DEF_RELEVANCE,0, opt_json_status,
			ARG_VALUE_FORM,	HLP_ARG_RELEVANCE}
};


static void json_cleanup( void )
{

        if (current_update_interval) {
                set_route_change_hooks(json_route_change_hook, DEL);
        }

}



static int32_t json_init( void ) {

        register_options_array(json_options, sizeof ( json_options), CODE_CATEGORY_NAME);


	return SUCCESS;
}


struct plugin* get_plugin( void ) {
	
	static struct plugin json_plugin;
	
	memset( &json_plugin, 0, sizeof ( struct plugin ) );
	

	json_plugin.plugin_name = CODE_CATEGORY_NAME;
	json_plugin.plugin_size = sizeof ( struct plugin );
	json_plugin.cb_init = json_init;
	json_plugin.cb_cleanup = json_cleanup;
        json_plugin.cb_plugin_handler[PLUGIN_CB_DESCRIPTION_CREATED] = (void (*) (int32_t, void*)) json_description_event_hook;
        json_plugin.cb_plugin_handler[PLUGIN_CB_DESCRIPTION_DESTROY] = (void (*) (int32_t, void*)) json_description_event_hook;
        json_plugin.cb_plugin_handler[PLUGIN_CB_CONF] = json_config_event_hook;
//      json_plugin.cb_plugin_handler[PLUGIN_CB_CONF] = json_dev_event_hook;
        json_plugin.cb_plugin_handler[PLUGIN_CB_BMX_DEV_EVENT] = json_dev_event_hook;
        json_plugin.cb_plugin_handler[PLUGIN_CB_STATUS] = json_status_event_hook;
        json_plugin.cb_plugin_handler[PLUGIN_CB_LINKS_EVENT] = json_links_event_hook;

	return &json_plugin;
}


