#!/bin/sh
# This script unseals a TPM2 sealed LUKS key using the TPM2 tool.
/usr/bin/tpm2_unseal -c 0x81000001 -p pcr:sha256:0,7,16
