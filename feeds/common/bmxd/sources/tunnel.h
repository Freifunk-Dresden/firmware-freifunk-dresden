

void init_tunnel(void);
void process_tun_ogm(struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router);
void trigger_tun_update(void);
void flush_tun_orig(struct orig_node *on);
void tun_cleanup(void);