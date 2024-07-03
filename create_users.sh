#!/bin/bash

# Step 1: Check if the script is being run as root, if not, request root access
echo "################# Checking if the script is being run as root..."
if [[ "$(id -u)" -ne 0 ]]; then
echo "This script needs to be run as root. Trying to elevate privileges..."
echo "################# Re-running the script with elevated privileges..."
sudo -E "$0" "$@"
exit
fi

# Step 2: Create the log and password files and set appropriate permissions
echo "################# Creating log and password files..."
secure_dir="/var/secure"
log_dir="/var/log"
log_file="/var/log/user_management.log"
password_file="/var/secure/user_passwords.csv"

if [[ ! -d "$log_dir" ]]; then # Check if the log directory exists
echo "################# Log dir does not exist: Creating log directory..."
mkdir "$log_dir"
else
echo "################# Log directory exists..."
fi

if [[ ! -d "$secure_dir" ]]; then # Check if the secure directory exists
echo "################# Secure dir does not exist: Creating secure directory..."
mkdir "$secure_dir"
else
echo "################# Secure directory exists..."
fi

touch "$log_file"
touch "$password_file"

echo "################# Setting permissions..."
chmod 640 "$log_file" # Only root and members of root's group can read and write, others cannot access
chmod 600 "$password_file" # Only root can read and write

# Step 3: Log all the commands and their output to the file in /var/log/ called user_management.log
echo "################# Logging all the commands and their output..."
exec > >(tee -a "$log_file") 2>&1

# Step 4: Prompt the user to enter the name of the file containing the list of users and groups if not provided as an argument
echo "################# Prompting for the file containing the list of users and groups..."
user_file=$1
if [[ -z "$user_file" ]]; then
read -p "Enter the name of the file containing the list of users and groups with its full path: " user_file
fi

# Step 5: Check if the file exists, if not exit the script, else proceed
echo "################# Checking if the file exists..."
if [[ ! -f "$user_file" ]]; then
echo "################ Error: The file does not exist. Please provide a valid file name."
exit 1
else
echo "################ File exists. Proceeding with the script..."
fi

# Step 6: Create a function to create random passwords for the users
echo "################# Creating a function to generate random passwords..."
generate_password() {
# Generate a random password using openssl
openssl rand -base64 8
}

# Step 7: Read the file line by line and create users with a home directory and random password and add them to the appropriate groups
echo "################# Reading the file and creating users..."
while IFS=";" read -r username groups; do
# Skip the line if it starts with a comment
echo "################# Checking if line is a comment..."
[[ "$username" =~ ^#.*$ ]] && continue

# Skip the line if the username or groups is empty
echo "################# Checking if the username or groups is empty..."
[[ -z "$username" || -z "$groups" ]] && continue

# Remove leading and trailing whitespaces
echo "################# Removing leading and trailing whitespaces..."
username=$(echo "$username" | xargs)
groups=$(echo "$groups" | xargs)

echo "################# Processing user: $username..."

# Check if the user already exists
echo "################# Checking if $username already exists..."
if id "$username" &>/dev/null; then
   echo "################ User $username already exists. Skipping..."
   continue
fi

# Generate a random password
echo "################ Generating a random password for new user..."
password=$(generate_password)

# Encrypt the password
echo "################ Encrypting newly generated password to pass to the user with the -p flag..."
encrypted_password=$(openssl passwd -6 "$password")

# Create the user with the encrypted password
echo "################ Creating $username with the encrypted password..."
if useradd -m -p "$encrypted_password" "$username"; then
   echo "################ User $username created with password"
else
   echo "################ Error creating user $username"
   continue
fi

# Split groups by comma and iterate over each group
echo "################ Splitting $groups with ',' into an array of groups..."
IFS=',' read -ra ADDR <<< "$groups"
for group in "${ADDR[@]}"; do

# Remove leading and trailing whitespaces
echo "################ Removing leading and trailing whitespaces..."
group=$(echo "$group" | xargs)

   # Check if the group exists, if not, create the group
   echo "################ Checking if $group exists..."
   if ! getent group "$group" > /dev/null 2>&1; then
      groupadd "$group"
      echo "Group $group created."
   fi

   # Add the user to the specified group
   echo "Adding $username to $group..."
   if ! usermod -aG "$group" "$username"; then
      echo "################# Error adding $username to $group..."
   else
      echo "################# User $username added to group $group..."
   fi
done

# Store the username and encrypted password in the password file
echo "$username,$password" >> "$password_file"
done < "$user_file"

echo "################# User creation process completed successfully."