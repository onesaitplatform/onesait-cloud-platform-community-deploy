echo "[Creating self signed certificates - Step 1]${green}############################ Creating self signed certificates...${reset}"

# Set IP and COMMONNAME
export IP="172.22.11.203"
export COMMONNAME="localhost"
# Comment SO not used
SEP="//" # WINDOWS
#SEP="" # OTHERS

# Define where to store the generated certs and metadata.
DIR="$(pwd)/tls"

# Optional: Ensure the target directory exists and is empty.
rm -rf "${DIR}"
mkdir -p "${DIR}"

# Create the openssl configuration file. This is used for both generating
# the certificate as well as for specifying the extensions. It aims in favor
# of automation, so the DN is encoding and not prompted.
cat > "${DIR}/openssl.cnf" << EOF
[req]
default_bits = 2048
encrypt_key  = no # Change to encrypt the private key using des3 or similar
default_md   = sha256
prompt       = no
utf8         = yes
# Specify the DN here so we aren't prompted (along with prompt = no above).
distinguished_name = req_distinguished_name
# Extensions for SAN IP and SAN DNS
req_extensions = v3_req
# Be sure to update the subject to match your organization.
[req_distinguished_name]
C  = ES
ST = MyCompany
L  = Madrid
O  = MyOrganization
CN = $COMMONNAME
# Allow client and server auth. You may want to only allow server auth.
# Link to SAN names.
[v3_req]
basicConstraints     = CA:FALSE
subjectKeyIdentifier = hash
keyUsage             = critical, nonRepudiation, digitalSignature, keyEncipherment, keyAgreement
extendedKeyUsage     = clientAuth, serverAuth
subjectAltName       = @alt_names
# Alternative names are specified as IP.# and DNS.# for IP addresses and
# DNS accordingly. 
[alt_names]
IP.1  = $IP 
DNS.1 = $COMMONNAME
EOF

# Create the certificate authority (CA). This will be a self-signed CA, and this
# command generates both the private key and the certificate. You may want to 
# adjust the number of bits (4096 is a bit more secure, but not supported in all
# places at the time of this publication). 
#
# To put a password on the key, remove the -nodes option.
#
# Be sure to update the subject to match your organization.
echo "# openssl req ..."
openssl req \
  -new \
  -newkey rsa:2048 \
  -days 120 \
  -nodes \
  -x509 \
  -subj "${SEP}C=ES/ST=MyCompany/L=Madrid/O=MyOrganization/CN=${COMMONNAME}" \
  -keyout "${DIR}/cacert.key" \
  -out "${DIR}/cacert.crt"
#
# For each server/service you want to secure with your CA, repeat the
# following steps:
#

# Generate the private key for the service. Again, you may want to increase
# the bits to 4096.
echo "# openssl genrsa ..."
openssl genrsa -out "${DIR}/selfsigned.key" 2048

# Generate a CSR using the configuration and the key just generated. We will
# give this CSR to our CA to sign.
echo "# openssl req ..."
openssl req \
  -new -key "${DIR}/selfsigned.key" \
  -out "${DIR}/selfsigned.csr" \
  -config "${DIR}/openssl.cnf"
  
# Sign the CSR with our CA. This will generate a new certificate that is signed
# by our CA.
echo "# openssl x509 ..."
openssl x509 \
  -req \
  -days 120 \
  -in "${DIR}/selfsigned.csr" \
  -CA "${DIR}/cacert.crt" \
  -CAkey "${DIR}/cacert.key" \
  -CAcreateserial \
  -extensions v3_req \
  -extfile "${DIR}/openssl.cnf" \
  -out "${DIR}/selfsigned.crt"

# (Optional) Verify the certificate.
echo "# openssl x509 -in ..."
openssl x509 -in "${DIR}/selfsigned.crt" -noout -text

echo "[Creating self signed certificates - Step 2]${green}############################ Copying self signed certificates...${reset}"
