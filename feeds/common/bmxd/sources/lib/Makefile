
PLUGINS = $(shell find  -maxdepth 1 -type d | grep -e '^./bmx_' | sort)

%:
	for d in $(PLUGINS); do $(MAKE) -C $$d $@ || echo compiling $$d failed; echo;echo; done
