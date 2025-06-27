#!/bin/sh

# This script generates a set of keys (PK, KEK, db) required for
# setting up UEFI Secure Boot with custom keys. It is written to be
# POSIX-compliant and should run with /bin/sh. 
#
# It produces both .esl (EFI Signature List) and .auth (Authenticated
# Variable) files. Check your UEFI firmware documentation to see which
# file type you need to enroll.
#
# NOTE: You will be prompted to create and verify a password for each of
# the three private keys (PK, KEK, db).
#
# Requirements:
# - OpenSSL (for key generation and signing)
# - efitools (for converting to EFI Signature List and signing)

# Strict mode: exit on error, exit on unset variable.
set -eu

#
# User Input

printf "Enter a Common Name (CN) for the keys: "
read -r CN_NAME
echo "Using Common Name: '$CN_NAME'"
echo "----------------------------------------------------"

#
# Key Generation (with Password Protection)

echo "1. Generating Platform Key (PK)..."
echo "   You will be asked to create a password for the PK private key."
if ! openssl req -new -x509 -newkey rsa:2048 -days 3650 \
    -keyout PK.key -out PK.crt -subj "/CN=$CN_NAME PK/"; then
    echo "Error: Failed to create Platform Key." >&2
    exit 1
fi

echo ""
echo "2. Generating Key Exchange Key (KEK)..."
echo "   You will be asked to create a password for the KEK private key."
if ! openssl req -new -x509 -newkey rsa:2048 -days 3650 \
    -keyout KEK.key -out KEK.crt -subj "/CN=$CN_NAME KEK/"; then
    echo "Error: Failed to create Key Exchange Key." >&2
    exit 1
fi

echo ""
echo "3. Generating Signature Database key (db)..."
echo "   You will be asked to create a password for the db private key."
if ! openssl req -new -x509 -newkey rsa:2048 -days 3650 \
    -keyout db.key -out db.crt -subj "/CN=$CN_NAME db/"; then
    echo "Error: Failed to create Signature Database key." >&2
    exit 1
fi

echo ""
echo "All keys (.key) and certificates (.crt) generated successfully."
echo "----------------------------------------------------"

#
# Formatting for UEFI

echo "4. Generating Globally Unique Identifier (GUID)..."
GUID=$(cat /proc/sys/kernel/random/uuid)
echo "$GUID" > GUID.txt
echo "GUID ($GUID) saved to GUID.txt"
echo ""

echo "5. Converting certificates to EFI Signature List format (.esl)..."
if ! cert-to-efi-sig-list -g "$GUID" PK.crt PK.esl; then
    echo "Error: Failed to convert PK certificate to .esl." >&2
    exit 1
fi
if ! cert-to-efi-sig-list -g "$GUID" KEK.crt KEK.esl; then
    echo "Error: Failed to convert KEK certificate to .esl." >&2
    exit 1
fi
if ! cert-to-efi-sig-list -g "$GUID" db.crt db.esl; then
    echo "Error: Failed to convert db certificate to .esl." >&2
    exit 1
fi

echo "Certificates converted to .esl format."
echo "----------------------------------------------------"

#
# Signing for Enrollment (.auth files)

echo "6. Creating signed files for firmware enrollment (.auth)..."
echo ""

# The PK signs updates to itself and to the KEK database.
# The KEK signs updates to the db database.
echo "You will be asked for PK.key password."
if ! sign-efi-sig-list -k PK.key -c PK.crt PK PK.esl PK.auth; then
    echo "Error: Failed to sign PK list." >&2
    exit 1
fi
echo "You will be asked for PK.key password."
if ! sign-efi-sig-list -k PK.key -c PK.crt KEK KEK.esl KEK.auth; then
    echo "Error: Failed to sign KEK list." >&2
    exit 1
fi
echo "You will be asked for KEK.key password."
if ! sign-efi-sig-list -k KEK.key -c KEK.crt db db.esl db.auth; then
    echo "Error: Failed to sign db list." >&2
    exit 1
fi

echo "Signed .auth files created."
echo "----------------------------------------------------"
echo ""

#
# Move generated files into organized subdirectories

echo "Organizing files into subdirectories..."
mkdir -p keys certs esl auth
mv PK.key KEK.key db.key keys/
mv PK.crt KEK.crt db.crt certs/
mv PK.esl KEK.esl db.esl esl/
mv PK.auth KEK.auth db.auth auth/

#
# Final Instructions

echo "Success! All keys and signatures created and organized."
echo ""
echo "Next Steps: Enroll the appropriate files in your UEFI firmware."
echo "================================================================="
echo "Depending on your firmware, you will need either the EFI Signature"
echo "Lists (.esl) or the signed Authenticated Variables (.auth)."
echo ""
echo "    - Platform Key (PK):      esl/PK.esl or auth/PK.auth"
echo "    - Key Exchange Key (KEK): esl/KEK.esl or auth/KEK.auth"
echo "    - Signature DB Key (db):  esl/db.esl or auth/db.auth"
echo ""
echo "Terramaster F4-424 Pro uses .esl files for enrollment."
echo ""
echo "IMPORTANT: Store the passwords for your .key files in a secure"
echo "location. If you lose them, you will not be able to sign new"
echo "binaries or update your keys."
echo "================================================================="