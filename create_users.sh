#!/bin/bash

# Variables
USER_FILE="$1"
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.csv"

# Ensure the script is run with sudo privileges
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Please run as root"
    sudo -E "$0" "$@"
    exit 1
fi

# Function to log messages
log_message() {
    local MESSAGE="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $MESSAGE" >> "$LOG_FILE"
}

# Check if the user file exists
if [[ ! -f "$USER_FILE" ]]; then
    log_message "Error: User file $USER_FILE not found."
    exit 1
fi

# Ensure the secure directory exists
mkdir -p /var/secure
chmod 700 /var/secure

# Clear the previous password file and log file
: > "$PASSWORD_FILE"
: > "$LOG_FILE"

# Loop through each line in the user file
while IFS=';' read -r USER GROUPS; do
    USER=$(echo "$USER" | xargs) # Remove leading/trailing whitespace
    GROUPS=$(echo "$GROUPS" | xargs) # Remove leading/trailing whitespace
    
    # Check if the user already exists
    if id -u "$USER" >/dev/null 2>&1; then
        log_message "User $USER already exists. Skipping."
        continue
    fi

    # Create a personal group for the user if it doesn't exist
    if ! getent group "$USER" >/dev/null; then
        groupadd "$USER"
        log_message "Group $USER created."
    fi

    # Create additional groups if they don't exist
    IFS=',' read -ra GROUP_ARRAY <<< "$GROUPS"
    for GROUP in "${GROUP_ARRAY[@]}"; do
        GROUP=$(echo "$GROUP" | xargs) # Remove leading/trailing whitespace
        if ! getent group "$GROUP" >/dev/null; then
            groupadd "$GROUP"
            log_message "Group $GROUP created."
        fi
    done

    # Create the user with the specified groups, including their personal group
    useradd -m -g "$USER" -G "$GROUPS" "$USER"
    if [[ $? -ne 0 ]]; then
        log_message "Error: Failed to create user $USER."
        continue
    fi

    # Generate a random password
    PASSWORD=$(openssl rand -base64 12)
    echo "$USER:$PASSWORD" | chpasswd
    if [[ $? -ne 0 ]]; then
        log_message "Error: Failed to set password for $USER."
        continue
    fi

    # Save the password securely in CSV format
    echo "$USER,$PASSWORD" >> "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"

    # Set up home directory permissions
    chmod 700 "/home/$USER"
    chown "$USER:$USER" "/home/$USER"

    log_message "User $USER created with groups $GROUPS."
done < "$USER_FILE"

log_message "User creation process completed."