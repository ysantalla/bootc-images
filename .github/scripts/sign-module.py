#!/usr/bin/env python3
"""Signs a kernel module: sign-module.py <module> <certificate, PEM or DER> <private key>

The password of the key is in MODULE_KEY_PASSWORD. Same result as the kernel's scripts/sign-file,
but that program comes from a build that runs code from outside this repository, and this runs
next to the key.
"""

import struct
import subprocess
import sys
import tempfile

MAGIC = b"~Module signature appended~\n"
ELF = b"\x7fELF"
PKEY_ID_PKCS7 = 2


def main(module, certificate, key):
    with open(module, "rb") as file:
        data = file.read()
    if not data.startswith(ELF) or data.endswith(MAGIC):
        sys.exit(f"{module} is not an unsigned module")
    der = open(certificate, "rb").read()
    with tempfile.NamedTemporaryFile(suffix=".pem") as pem:
        # openssl cms only reads PEM certificates on older versions
        inform = "PEM" if der.startswith(b"-----") else "DER"
        subprocess.run(["openssl", "x509", "-inform", inform, "-in", certificate, "-out", pem.name], check=True)
        signature = subprocess.run(
            ["openssl", "cms", "-sign", "-binary", "-noattr", "-nocerts", "-nosmimecap", "-md", "sha256",
             "-signer", pem.name, "-inkey", key, "-passin", "env:MODULE_KEY_PASSWORD", "-outform", "DER", "-in", module],
            check=True, stdout=subprocess.PIPE,
        ).stdout
        # The kernel's own check, as far as openssl can make it: these bytes, this certificate
        with tempfile.NamedTemporaryFile() as detached:
            detached.write(signature)
            detached.flush()
            subprocess.run(
                ["openssl", "cms", "-verify", "-binary", "-inform", "DER", "-in", detached.name, "-content", module,
                 "-certfile", pem.name, "-nointern", "-noverify", "-out", "/dev/null"],
                check=True,
            )
    # struct module_signature: algo, hash, id_type, signer_len, key_id_len, three of padding, sig_len
    trailer = struct.pack(">BBBBB3xI", 0, 0, PKEY_ID_PKCS7, 0, 0, len(signature))
    with open(module, "ab") as file:
        file.write(signature + trailer + MAGIC)


if __name__ == "__main__":
    main(*sys.argv[1:])
