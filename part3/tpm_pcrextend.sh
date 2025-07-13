#!/bin/sh
# Extend PCR 16 with a random value
/usr/bin/tpm2_pcrextend 16:sha256="$(tpm2_getrandom 32 --hex)"
