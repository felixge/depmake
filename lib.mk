SHELL := /bin/bash

define dm_packets
PACKETS := $(basename $(notdir $(wildcard $(DM_PACKETS_DIR)/*.sh)))
ALL: $$(PACKETS)
$$(PACKETS):
	@source $(DM_DIR)/lib.sh && dm_build $$@ $$^

.PHONY: ALL $$(PACKETS)
endef
