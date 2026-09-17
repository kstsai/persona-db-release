#!/bin/bash
# Install WSL public key onto lzcdh5 (ubuntu) so subsequent ssh is key-based.
KEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC5Pc6lXBup7DBYYs3KjtThyCqvgSbErjREdETPCAvL7TnY+gmY5GvauIvldtuJw4oNB7C2ntc1ys4ArrzVzN//PXvm6ScMOhKe3S9+w0x4Wycikc2ur9SA7b75PdmfB3WZ1zv4zx8nScNcsJfdZjg97p7+jqSYCEBlbsEB0nTXDq33aFHPLWxha1wWZUNfX9AZFbsrtWHR/inX/bLObcL0mwJvpzJcue2ew/4yZprgLWTo85JTLkM7mBJEUiy4nxx/5iGSTBg6J4vc05o8yY9T0HL88ZkIRRpIbZy5pdqqRXwKQx3lN5ymdhReoNxnPZ+a2KSpUjIxbzlTB3+FPGkVV9+RFssbr3kR9lIeou2xkgrCT24uRQfcsfngw/uPUdBp1BaVar7kyhk61KnBr+tlsXlVvlb9NuMPT8dDrFQLvDID6BXswWclMcLuH6EleqMuTYLDZDUxdk6MJ7Cn4qydTj7VTE3ew1Sl9AAWR1300doqKSzL5veQQSdTrnul3+0= kstsai@bangoo'
ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 ubuntu@100.96.79.33 \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qF 'kstsai@bangoo' ~/.ssh/authorized_keys 2>/dev/null || echo '$KEY' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; echo KEY_INSTALLED_OK; hostname; whoami"
echo "SSH_EXIT=$?"
