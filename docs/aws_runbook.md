# AWS EC2 F2 runbook — prepared, not deployed

[[00-Roadmap]] · [[verification_plan]] · [[benchmark_method]]

**Current boundary:** local RTL/host inference passes. Source transformation was tested against nine exact files from the pinned upstream template; `reports/aws_staging.json` records that limited check. No complete HDK environment, vendor-IP simulation, Vivado run, AFI, or physical FPGA is verified. Neither `aws` CLI nor Vivado was available in this Mac session. No account credentials were used and no AWS resources were launched.

## 1. Approve the cloud experiment before spending

Choose an AWS account/profile, supported region, F2 quota, maximum total spend, maximum build/runtime hours and cleanup owner. Confirm the current instance and EBS/S3 rates in that region. Do not assume a price or AMI ID from an old tutorial. A build can run on a suitable x86-64 machine; physical execution needs F2. AWS's [developer-kit guide](https://github.com/aws/aws-fpga/blob/f2/User_Guide_AWS_EC2_FPGA_Development_Kit.md) describes compatible AMIs/tools; [F2 specifications](https://aws.amazon.com/ec2/instance-types/f2/) describe available FPGA sizes.

Use `python3 scripts/budget_check.py --help` to check a proposed compute allowance plus storage reserve. This is an arithmetic planning check, **not a billing limit or automatic shutdown**. Configure account budget notifications separately. Agree on an instance-stop deadline, tag resources `Project=NPU-1`, and arrange a real stop mechanism/owner. EBS and retained storage can keep charging after an instance stops. Avoid speculative provisioning or long-running unattended builds.

Use IAM roles or your normal AWS profile; never commit keys. Restrict the S3 bucket to the project and follow AWS's AFI service access requirements rather than making it public. Obtain only the permissions needed for the approved EC2/S3/AFI work. The current project has no infrastructure provisioning script.

## 2. Reproduce the official baseline on Linux x86-64

After cloud approval, create the chosen developer environment. Keep the checkout path free of spaces. Install/activate a Vivado version supported by the pinned developer kit.

```sh
git clone --branch f2 https://github.com/aws/aws-fpga.git
cd aws-fpga
git checkout c34f88e97eaf8a9b6ea7a3516ab65ee64690ab82
source hdk_setup.sh
source sdk_setup.sh
```

Record `git rev-parse HEAD`, `vivado -version`, OS, AMI, instance type and region. HDK setup may download shell files and generate IP; it is not a local Mac command. Reconcile any unsupported tool version before proceeding.

Set CL_DIR to the official `hdk/cl/examples/cl_demo/cl_axil_reg_access` directory. Run its unmodified simulator tests following the bundled verification README. With the matching XSim environment the intended command is:

```sh
export CL_DIR="$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_demo/cl_axil_reg_access"
cd "$CL_DIR/verif/scripts"
make TEST=test_null SIMULATOR=xsim
```

If the pinned make system needs additional simulator setup, follow its own README/Makefile help; do not replace shell simulation with a small local OCL wrapper and call it equivalent. Preserve the complete log and establish the original example works before changing it.

## 3. Stage NPU-1

From the NPU repository (set NPU_DIR to that absolute path):

```sh
export NPU_DIR="$PWD"
python3 scripts/stage_aws_cl.py \
  --aws-dir "$AWS_FPGA_REPO_DIR" \
  --output "$NPU_DIR/aws/staged/cl_axil_reg_access"
export CL_DIR="$NPU_DIR/aws/staged/cl_axil_reg_access"
python3 scripts/check_aws_staging.py "$CL_DIR"
```

The output must not exist and must end in `cl_axil_reg_access`: the official build requires the directory and CL module names to match. The NPU package intentionally retains that vendor template name while replacing its application datapath. The hardware ID register still identifies NPU-1. This avoids fragile wholesale renaming of the vendor scripts.

The staging tool checks the exact HDK commit and template hashes, retains real `cl_ports.vh` ports, PCI identification, unused-interface tie-offs, the OCL AXI register slice and debug bridge, adds a synchronized reset release, replaces the adder with `npu_axil`, and inserts all NPU sources in package-first order. It removes the original adder-specific assertion binding and stages `test_npu.sv`. The original checkout is not modified. The copied vendor files keep their upstream license notices.

```sh
cd "$CL_DIR/verif/scripts"
make TEST=test_npu SIMULATOR=xsim
```

**Gate:** the real shell test must check ID, a 4×4 GEMM, bounded completion and all results. This test has been prepared but not run with AWS's shell/IP libraries. Add additional reset/PCIe testing before deployment. Do not use the original adder runtime against the NPU register map.

## 4. Build and inspect implementation

```sh
cd "$CL_DIR/build/scripts"
python3 "$HDK_SHELL_DIR/build/scripts/aws_build_dcp_from_cl.py" --help
python3 "$HDK_SHELL_DIR/build/scripts/aws_build_dcp_from_cl.py" \
  --cl cl_axil_reg_access --mode small_shell
```

The pinned [HDK instructions](https://github.com/aws/aws-fpga/blob/c34f88e97eaf8a9b6ea7a3516ab65ee64690ab82/hdk/README.md) supply the build flow. Keep the shell's clock, placement and interface constraints. `aws/constraints/npu_user.xdc` is additive guidance, not a substitute shell timing model. This design uses the shell's 250 MHz `clk_main_a0`; **meeting its 4 ns constraint is unverified**. There is no custom clock generator in this first version.

Review the synthesis and implementation reports for RAM/DSP mapping, latches, multiple drivers, unconstrained endpoints, DRC, clock/reset paths and setup/hold timing. The long requantization path may need pipelining. A tarball can be produced even with a timing-violated DCP; reject such a result. Never false-path computation just to obtain a passing report.

Preserve source/staging hashes, build logs, utilization, timing summary, post-route DCP and its generated `*.Developer_CL.tar` package. Check the actual filenames under `$CL_DIR/build/checkpoints` and `build/reports`; do not guess timestamps.

## 5. Create the AFI (authorized cloud action)

Choose an approved bucket/region and unique object names. Set these variables to actual reviewed values; there are no usable default bucket names or image IDs in this project.

```sh
# Set NPU_REGION, NPU_BUCKET, NPU_DCP_TAR and NPU_DCP_KEY first.
aws s3 cp "$NPU_DCP_TAR" "s3://$NPU_BUCKET/$NPU_DCP_KEY" --region "$NPU_REGION"
aws ec2 create-fpga-image --region "$NPU_REGION" \
  --name npu-1 \
  --input-storage-location "Bucket=$NPU_BUCKET,Key=$NPU_DCP_KEY" \
  --logs-storage-location "Bucket=$NPU_BUCKET,Key=npu-1/afi-logs/" \
  > npu-1-afi.json
```

AFI creation is asynchronous. Record both `afi-...` and `agfi-...` from the returned JSON. Use `aws ec2 describe-fpga-images --fpga-image-ids "$NPU_AFI" --region "$NPU_REGION"`; wait for State.Code=`available`, inspect failure reasons and logs otherwise. Follow the [AFI API](https://docs.aws.amazon.com/cli/latest/reference/ec2/create-fpga-image.html) and [AWS image guide](https://github.com/aws/aws-fpga/blob/f2/hdk/docs/Amazon_FPGA_Images_Afis_Guide.md) for permissions and service details. A source manifest is not an AFI.

## 6. Load and validate on F2

Use a dedicated approved FPGA slot. Ensure it is not running someone else's job. After SDK setup on the F2 runtime host:

```sh
sudo fpga-describe-local-image -S 0 -H
sudo fpga-load-local-image -S 0 -I "$NPU_AGFI"
sudo fpga-describe-local-image -S 0 -H
```

Local loading uses **AGFI**, not the regional AFI identifier. Confirm `loaded` and correct image/PCI identity. Follow the SDK's rescan/permissions instructions if necessary.

From the NPU repository:

```sh
python3 scripts/make_fixtures.py /tmp/npu-1-fixtures.bin
make -C host -B AWS=1
# SDK runtime search path may be required; use the SDK's supported installation.
./host/npu_validate --aws /tmp/npu-1-fixtures.bin 0
```

`-B` forces rebuilding objects with AWS enabled, avoiding accidentally reusing a local stub build. The AWS SDK link uses `SDK_DIR/userspace/lib/so` and `libfpga_mgmt`. The host validates ID/ABI, applies bounded polling and propagates transport errors. The binary fixture is a trusted generated test artifact, not a general input interchange format.

The **same workload validator** used with Verilator is compiled into this CLI: randomized GEMMs and the full two-layer digits test at batch sizes 1 and 4. Actual hardware hidden activations feed the second layer. Only a passing hardware log paired with a known loaded image closes deployment verification.

## 7. Measure and shut down

Follow [[benchmark_method]]. Save measured data with the actual clock, AFI, source hashes and host environment. Record every approved resource in `docs/cost_log.csv`. Stop runtime F2 instances immediately after tests; stop build machines after copying needed artifacts. Review EBS volumes, snapshots, S3 objects, public IPs and other retained resources. Terminate/delete only the specific resources approved for cleanup. Verify the account's remaining billable inventory rather than assuming the end of a terminal session stopped billing.
