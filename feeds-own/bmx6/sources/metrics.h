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


#define MIN_DESC_METRICALGO           0
#define MAX_DESC_METRICALGO           1
#define DEF_DESC_METRICALGO           1
#define ARG_DESC_METRICALGO           "descMetricAlgo"

#define BIT_METRIC_ALGO_MIN           0x00
#define BIT_METRIC_ALGO_MP            0x00 // ->   1
#define BIT_METRIC_ALGO_EP            0x01 // ->   2
#define BIT_METRIC_ALGO_MB            0x02 // ->   4
#define BIT_METRIC_ALGO_EB            0x03 // ->   8
#define BIT_METRIC_ALGO_VB            0x04 // ->  16
#define BIT_METRIC_ALGO_MAX           0x04
#define BIT_METRIC_ALGO_ARRSZ         ((8*sizeof(ALGO_T)))

#define TYP_METRIC_ALGO_MP            (0x01 << BIT_METRIC_ALGO_MP)
#define TYP_METRIC_ALGO_EP            (0x01 << BIT_METRIC_ALGO_EP)
#define TYP_METRIC_ALGO_MB            (0x01 << BIT_METRIC_ALGO_MB)
#define TYP_METRIC_ALGO_EB            (0x01 << BIT_METRIC_ALGO_EB)
#define TYP_METRIC_ALGO_VB            (0x01 << BIT_METRIC_ALGO_VB)

#define MIN_METRIC_ALGO               0x00 // hop count
#define MAX_METRIC_ALGO               (0x01 << BIT_METRIC_ALGO_MAX)
#define MAX_METRIC_ALGO_RESERVED      ((ALGO_T)-1);
#define DEF_METRIC_ALGO               TYP_METRIC_ALGO_VB

#define ARG_PATH_METRIC_ALGO "metricAlgo"
#define CHR_PATH_METRIC_ALGO 'M'
#define HELP_PATH_METRIC_ALGO "set metric algo for routing towards myself:\n        0:HopCount  1:MP (M=1 /R=0 /T=1 /t=1 <=> TQ) 2:EP  4:MB  8:EB (M=8 /R=1 /r=1 /T=1 /t=1 <=> ETT)  16:VB"


#define MIN_PATH_XP_EXP_NUMERATOR     0
#define MAX_PATH_XP_EXP_NUMERATOR     3
#define MIN_PATH_XP_EXP_DIVISOR       1
#define MAX_PATH_XP_EXP_DIVISOR       2


#define DEF_PATH_RP_EXP_NUMERATOR     1
#define ARG_PATH_RP_EXP_NUMERATOR     "rxExpNumerator"
#define CHR_PATH_RP_EXP_NUMERATOR     'R'

#define DEF_PATH_RP_EXP_DIVISOR       2
#define ARG_PATH_RP_EXP_DIVISOR       "rxExpDivisor"
#define CHR_PATH_RP_EXP_DIVISOR       'r'

#define DEF_PATH_TP_EXP_NUMERATOR     1
#define ARG_PATH_TP_EXP_NUMERATOR     "txExpNumerator"
#define CHR_PATH_TP_EXP_NUMERATOR     'T'

#define DEF_PATH_TP_EXP_DIVISOR       1
#define ARG_PATH_TP_EXP_DIVISOR       "txExpDivisor"
#define CHR_PATH_TP_EXP_DIVISOR       't'

#define MAX_PATH_WINDOW 250      /* 250 TBD: should not be larger until ogm->ws and neigh_node.packet_count (and related variables) is only 8 bit */
#define MIN_PATH_WINDOW 1
#define DEF_PATH_WINDOW 5        /* NBRF: NeighBor Ranking sequence Frame) sliding packet range of received orginator messages in squence numbers (should be a multiple of our word size) */
#define ARG_PATH_WINDOW "pathWindow"
//extern int32_t my_path_window; // my path window size used to quantify the end to end path quality between me and other nodes

#define MIN_PATH_LOUNGE 0
#define MAX_PATH_LOUNGE 10
#define DEF_PATH_LOUNGE 1
#define ARG_PATH_LOUNGE "pathLounge"
//extern int32_t my_path_lounge;


#define DEF_PATH_REGRESSION_SLOW 1
#define MIN_PATH_REGRESSION_SLOW 1
#define MAX_PATH_REGRESSION_SLOW 255
#define ARG_PATH_REGRESSION_SLOW "pathRegression"



//#define RP_LINK_LOUNGE 0  /* may also be rtq_link_lounge */

/*
// this deactivates OGM-Acks on the link:
#define MIN_LINK_IGNORE_MIN  0
#define MAX_LINK_IGNORE_MIN  100
#define DEF_LINK_IGNORE_MIN  50
#define ARG_LINK_IGNORE_MIN "link_ignore_min"
//extern int32_t link_ignore_min;

// this activates OGM-Acks on the link:
#define MIN_LINK_IGNORE_MAX  0
#define MAX_LINK_IGNORE_MAX  255
#define DEF_LINK_IGNORE_MAX  100
#define ARG_LINK_IGNORE_MAX "link_ignore_max"
//extern int32_t link_ignore_max;
*/


#define MIN_PATH_HYST	0
#define MAX_PATH_HYST	255
#define DEF_PATH_HYST	0
#define ARG_PATH_HYST   "pathHysteresis"
//extern int32_t my_path_hystere;


#define MIN_LATE_PENAL 0
#define MAX_LATE_PENAL 100
#define DEF_LATE_PENAL 1
#define ARG_LATE_PENAL "latenessPenalty"
//extern int32_t my_late_penalty;


#define DEF_HOP_PENALTY 0 //(U8_MAX/20) <=>  5% penalty on metric per hop
#define MIN_HOP_PENALTY 0 // smaller values than 4 do not show effect
#define MAX_HOP_PENALTY U8_MAX
#define ARG_HOP_PENALTY "hopPenalty"
#define MAX_HOP_PENALTY_PRECISION_EXP 8
//extern int32_t my_hop_penalty;


#define DEF_NEW_RT_DISMISSAL 99
#define MIN_NEW_RT_DISMISSAL 0
#define MAX_NEW_RT_DISMISSAL 200
#define ARG_NEW_RT_DISMISSAL "newRouterDismissal"
#define HLP_NEW_RT_DISMISSAL "dismiss new routers according to specified percentage"

#define MIN_PATH_UMETRIC_MIN UMETRIC_MIN__NOT_ROUTABLE
#define MAX_PATH_UMETRIC_MIN I32_MAX
#define ARG_PATH_UMETRIC_MIN "pathMetricMin"
#define DEF_PATH_UMETRIC_MIN MIN_PATH_UMETRIC_MIN

#define RP_ADV_DELAY_TOLERANCE 3000
#define RP_ADV_DELAY_RANGE     20000
#define TP_ADV_DELAY_TOLERANCE 3000
#define TP_ADV_DELAY_RANGE     20000


//#define TYP_METRIC_FLAG_STRAIGHT (0x1<<0)

#define MIN_METRIC_FLAGS          (0x0)
#define MAX_METRIC_FLAGS          (0x1)

#define DEF_PATH_METRIC_FLAGS     (0x0)
#define ARG_PATH_METRIC_FLAGS     "pathMetricFlags"

#define DEF_LINK_METRIC_FLAGS     (0x0)
#define ARG_LINK_METRIC_FLAGS     "linkMetricFlags"




struct mandatory_tlv_metricalgo { // 16 bytes

	FMETRIC_U16_T fmetric_u16_min;      // 2 bytes

	uint16_t reserved;                  // 2 bytes

	ALGO_T algo_type;                   // 2 bytes

        uint16_t flags;                     // 2 bytes

#if __BYTE_ORDER == __LITTLE_ENDIAN         // 1 byte
	unsigned int tp_exp_divisor : 2;
	unsigned int tp_exp_numerator : 2;
	unsigned int rp_exp_divisor : 2;
	unsigned int rp_exp_numerator : 2;
#elif __BYTE_ORDER == __BIG_ENDIAN
	unsigned int rp_exp_numerator : 2;
	unsigned int rp_exp_divisor : 2;
	unsigned int tp_exp_numerator : 2;
	unsigned int tp_exp_divisor : 2;
#else
# error "Please fix <bits/endian.h>"
#endif

        uint8_t reserved2;                  // 1 byte
	uint8_t path_window_size;           // 1 byte
	uint8_t path_lounge_size;           // 1 byte
	uint8_t regression;                 // 1 byte
	uint8_t hystere;                    // 1 byte
	uint8_t hop_penalty;                // 1 byte
	uint8_t late_penalty;               // 1 byte

} __attribute__((packed));


struct description_tlv_metricalgo {
	struct mandatory_tlv_metricalgo m;
	uint8_t optional[];
} __attribute__((packed));

#define DESCRIPTION_MSG_METRICALGO_FORMAT { \
{FIELD_TYPE_HEX,  -1, (8*sizeof(FMETRIC_U16_T)),  0, FIELD_RELEVANCE_HIGH, "fmetric_u16_min"}, \
{FIELD_TYPE_UINT, -1, 16,  0, FIELD_RELEVANCE_LOW,  "reserved"},  \
{FIELD_TYPE_UINT, -1, 16,  0, FIELD_RELEVANCE_HIGH, ARG_PATH_METRIC_ALGO },  \
{FIELD_TYPE_HEX,  -1, 16,  0, FIELD_RELEVANCE_HIGH, "flags" },   \
{FIELD_TYPE_UINT, -1,  2,  1, FIELD_RELEVANCE_HIGH, ARG_PATH_TP_EXP_DIVISOR },   \
{FIELD_TYPE_UINT, -1,  2,  1, FIELD_RELEVANCE_HIGH, ARG_PATH_TP_EXP_NUMERATOR },   \
{FIELD_TYPE_UINT, -1,  2,  1, FIELD_RELEVANCE_HIGH, ARG_PATH_RP_EXP_DIVISOR },   \
{FIELD_TYPE_UINT, -1,  2,  1, FIELD_RELEVANCE_HIGH, ARG_PATH_RP_EXP_NUMERATOR },   \
{FIELD_TYPE_UINT, -1,  8,  1, FIELD_RELEVANCE_LOW,  "reserved2"},  \
{FIELD_TYPE_UINT, -1,  8,  1, FIELD_RELEVANCE_HIGH, ARG_PATH_WINDOW},  \
{FIELD_TYPE_UINT, -1,  8,  1, FIELD_RELEVANCE_HIGH, ARG_PATH_LOUNGE},  \
{FIELD_TYPE_UINT, -1,  8,  1, FIELD_RELEVANCE_HIGH, ARG_PATH_REGRESSION_SLOW},  \
{FIELD_TYPE_UINT, -1,  8,  1, FIELD_RELEVANCE_LOW , ARG_PATH_HYST},  \
{FIELD_TYPE_UINT, -1,  8,  1, FIELD_RELEVANCE_HIGH, ARG_HOP_PENALTY},  \
{FIELD_TYPE_UINT, -1,  8,  1, FIELD_RELEVANCE_LOW , ARG_LATE_PENAL},  \
FIELD_FORMAT_END }


extern struct host_metricalgo link_rp_metric_algo;


extern UMETRIC_T UMETRIC_NBDISCOVERY_MIN;
extern UMETRIC_T TX_UMETRIC_OGM_ACK_MIN;



// some tools:


FMETRIC_U16_T fmetric(uint8_t mantissa, uint8_t exp);

UMETRIC_T umetric(uint8_t mantissa, uint8_t exp);

UMETRIC_T fmetric_to_umetric(FMETRIC_U16_T fm);
FMETRIC_U16_T umetric_to_fmetric(UMETRIC_T val);
char *umetric_to_human(UMETRIC_T val);
FMETRIC_U16_T fmetric_u8_to_fmu16( FMETRIC_U8_T fmu8 );
FMETRIC_U8_T umetric_to_fmu8( UMETRIC_T *um );

IDM_T is_fmetric_valid(FMETRIC_U16_T fm);

IDM_T fmetric_cmp(FMETRIC_U16_T a, unsigned char cmp, FMETRIC_U16_T b);


// some core hooks:
//void apply_metric_algo(UMETRIC_T *out, struct link_dev_node *link, const UMETRIC_T *path, struct host_metricalgo *algo);

UMETRIC_T apply_metric_algo(UMETRIC_T *tr, UMETRIC_T *umetric_max, const UMETRIC_T *path, struct host_metricalgo *algo);
void lndev_assign_best(struct local_node *local, struct link_dev_node *lndev );
void update_link_probe_record(struct link_dev_node *lndev, HELLO_SQN_T sqn, uint8_t probe);

void metricalgo_remove(struct orig_node *on);
void metricalgo_assign(struct orig_node *on, struct host_metricalgo *host_algo);

IDM_T update_path_metrics(struct packet_buff *pb, struct orig_node *on, OGM_SQN_T in_sqn, UMETRIC_T *in_umetric);



// plugin hooks:

struct plugin *metrics_get_plugin( void );
