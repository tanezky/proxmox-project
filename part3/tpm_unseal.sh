#!/bin/sh
# Unseals a TPM2 sealed LUKS key
/usr/bin/tpm2_unseal -c 0x81000002 -p pcr:sha256:0,7,16
