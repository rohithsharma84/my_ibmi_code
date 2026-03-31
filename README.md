# my_ibmi
These are my experiments, use at your own risk.
Trying to learn CI/CD concepts to allow using git and branching model and Jenkins to build/deploy IBM i objects

yum and npm install did not like corporate self-signed cert that was doing TLS intercept. Installed corporate root CA by using the following commands:
$ cp ~./CorporateRoot.cer /etc/pki/ca-trust/source/anchors/
$ sudo update-ca-trust 

$ export NODE_EXTRA_CA_CERTS="/etc/pki/ca-trust/source/anchors/CorporateRoot.cer"
 