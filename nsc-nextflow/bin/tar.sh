delivery_location="/data/runScratch.boston/demultiplexed/delivery"

cd $1
tar -cvf $2.tar $2
md5sum $2.tar > $2.tar.md5
mkdir $delivery_location/$2
mv $1/$2.tar $1/$2.tar.md5 $delivery_location/$2

username=$(echo "$2" | sed -n 's/.*Project_\(.*\)-[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/\1/p' | tr '[:upper:]' '[:lower:]')
password=$(echo "$username" | cut -d'-' -f2)

echo "$username"
echo "$password"

# Write .htaccess file
cat <<EOL > "$delivery_location/$2/.htaccess"
AuthUserFile /data/$2/.htpasswd
AuthGroupFile /dev/null
AuthName ByPassword
AuthType Basic

<Limit GET>
require user $username
</Limit>
EOL
#

# Write .htpasswd file
hashed_password=$(openssl passwd -apr1 "$password")
echo "$username:$hashed_password" > "$delivery_location/$2/.htpasswd"
#