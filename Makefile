# SPDX-License-Identifier: GPL-3.0-or-later
CC ?= cc
AR ?= ar
CFLAGS ?= -O2
CPPFLAGS ?=
LDFLAGS ?=
LDLIBS ?=
WARNINGS = -Wall -Wextra -Wpedantic -Werror
INCLUDES = -Iinclude
BUILD = build

.PHONY: all test integration clean

all: $(BUILD)/libextfs.a $(BUILD)/extfs-tool $(BUILD)/test-extfs

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/extfs.o: core/extfs.c include/extfs/extfs.h | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARNINGS) -std=c11 $(INCLUDES) -c $< -o $@

$(BUILD)/libextfs.a: $(BUILD)/extfs.o
	$(AR) rcs $@ $^

$(BUILD)/extfs-tool.o: tools/extfs-tool.c include/extfs/extfs.h | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARNINGS) -std=c11 $(INCLUDES) -c $< -o $@

$(BUILD)/extfs-tool: $(BUILD)/extfs-tool.o $(BUILD)/libextfs.a
	$(CC) $(CFLAGS) $(LDFLAGS) $^ $(LDLIBS) -o $@

$(BUILD)/test-extfs.o: tests/test_extfs.c include/extfs/extfs.h | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARNINGS) -std=c11 $(INCLUDES) -c $< -o $@

$(BUILD)/test-extfs: $(BUILD)/test-extfs.o $(BUILD)/libextfs.a
	$(CC) $(CFLAGS) $(LDFLAGS) $^ $(LDLIBS) -o $@

test: all
	$(BUILD)/test-extfs
	$(MAKE) integration

integration: $(BUILD)/extfs-tool
	sh tests/integration.sh

clean:
	rm -rf $(BUILD)
