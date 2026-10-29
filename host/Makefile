CC ?= cc
CXX ?= c++
CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror -I.
CXXFLAGS := -std=c++17 -O2 -Wall -Wextra -Werror -I.
ifeq ($(AWS),1)
ifndef SDK_DIR
$(error Source aws-fpga/sdk_setup.sh first to set SDK_DIR)
endif
CFLAGS += -DAWS_FPGA -I$(SDK_DIR)/userspace/include
LDLIBS := -L$(SDK_DIR)/userspace/lib/so -lfpga_mgmt
endif
all: npu_validate
npu_validate: npu_runtime.o transport_aws.o validate.cpp workload.hpp
	$(CXX) $(CXXFLAGS) validate.cpp npu_runtime.o transport_aws.o $(LDLIBS) -o $@
%.o: %.c npu_runtime.h transport.h include/npu_regs.h
	$(CC) $(CFLAGS) -c $< -o $@
.PHONY: all
