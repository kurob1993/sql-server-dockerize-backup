#!/bin/bash

# Configuration
DEFAULT_SA_PASSWORD="mssql1Ipw"
BACKUP_DIR="/home/backup"
TEMP_DIR="/tmp"

# Global variables
CONTAINER_NAME=""
SA_PASSWORD=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get running SQL Server containers
get_sql_containers() {
    local containers=()

    for container in $(docker ps --format '{{.Names}}'); do
        local image=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null)

        if [[ "$image" =~ ^mcr\.microsoft\.com/mssql/server ]]; then
            if docker exec "$container" pgrep -f sqlservr > /dev/null 2>&1; then
                local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
                containers+=("$container"$'\t'"$image"$'\t'"$status")
            fi
        fi
    done

    if [ ${#containers[@]} -eq 0 ]; then
        print_warning "Tidak ditemukan container dengan image 'mcr.microsoft.com/mssql/server' yang menjalankan SQL Server"
        print_info "Menampilkan semua container yang sedang berjalan:"
        docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
    else
        printf "%s\n" "${containers[@]}"
    fi
}


# Function to validate container
validate_container() {
    local container_name="$1"
    
    if docker ps --format "{{.Names}}" | grep -q "^$container_name$"; then
        return 0
    else
        return 1
    fi
}

# Function to test SQL Server connection
test_sql_connection() {
    local container_name="$1"
    local password="$2"
    
    print_info "Testing SQL Server connection to container: $container_name"
    
    # Test connection with simple query
    docker exec "$container_name" /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$password" -Q "SELECT 1 AS TestConnection" > /dev/null 2>&1
    
    return $?
}

# Function to select container interactively
select_container() {
    echo
    print_info "Mendeteksi container SQL Server berdasarkan image resmi dan proses..."
    CONTAINER_LIST=$(get_sql_containers)

    if [ -z "$CONTAINER_LIST" ]; then
        print_error "Tidak ada container yang ditemukan."
        exit 1
    fi

    print_success "Running containers:"
    echo "----------------------------------------"
    printf "%-5s %-25s %-40s %-10s\n" "No." "Container Name" "Image" "Status"
    echo "----------------------------------------"

    local index=1
    declare -A container_map

    while IFS=$'\t' read -r name image status; do
        printf "%-5s %-25s %-40s %-10s\n" "$index" "$name" "$image" "$status"
        container_map["$index"]="$name"
        ((index++))
    done <<< "$CONTAINER_LIST"

    echo "----------------------------------------"
    read -p "Select container (enter number or container name): " selection

    # Jika input adalah angka
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        CONTAINER_NAME="${container_map[$selection]}"
    else
        CONTAINER_NAME="$selection"
    fi

    if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        print_error "Container '${CONTAINER_NAME}' not found or not running"
        select_container
    else
        print_success "Selected container: $CONTAINER_NAME"
    fi
}



# Function to get SA password
get_sa_password() {
    echo
    print_info "SQL Server Authentication Required"
    
    # Try default password first
    if test_sql_connection "$CONTAINER_NAME" "$DEFAULT_SA_PASSWORD"; then
        print_success "Connected using default password"
        SA_PASSWORD="$DEFAULT_SA_PASSWORD"
        return 0
    fi
    
    print_warning "Default password failed or SQL Server not ready"
    
    while true; do
        echo -n "Enter SA password: "
        read -s password
        echo
        
        if [ -z "$password" ]; then
            print_warning "Password cannot be empty"
            continue
        fi
        
        if test_sql_connection "$CONTAINER_NAME" "$password"; then
            print_success "Connection successful!"
            SA_PASSWORD="$password"
            break
        else
            print_error "Connection failed. Please check password and try again"
            echo -n "Try again? (y/N): "
            read -r retry
            if [[ ! "$retry" =~ ^[Yy]$ ]]; then
                print_error "Cannot proceed without valid SQL Server connection"
                exit 1
            fi
        fi
    done
}

# Function to get list of databases
get_databases() {
    print_info "Getting list of databases..."
    
    # Get database list using inline query
    DB_LIST=$(docker exec "$CONTAINER_NAME" /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb') AND state = 0 ORDER BY name;" -h -1 -W 2>/dev/null | grep -v "^$" | sed 's/^[ \t]*//;s/[ \t]*$//')
    
    echo "$DB_LIST"
}

# Function to validate database name
validate_database() {
    local db_name="$1"
    local db_list="$2"
    
    if echo "$db_list" | grep -q "^$db_name$"; then
        return 0
    else
        return 1
    fi
}

# Function to create backup directory in container
create_backup_dir() {
    print_info "Creating backup directory in container..."
    docker exec "$CONTAINER_NAME" mkdir -p "$BACKUP_DIR" 2>/dev/null
    if [ $? -eq 0 ]; then
        print_success "Backup directory created/verified"
    else
        print_warning "Could not create backup directory (might already exist)"
    fi
}

# Function to create backup SQL script
create_backup_script() {
    local database_name="$1"
    local backup_path="$2"
    local backup_filename="$3"
    
    # Create SQL script file
    cat > /tmp/backup_database.sql << 'SQLEOF'
SET NOCOUNT ON;
PRINT 'Starting backup process...';

DECLARE @BackupPath NVARCHAR(500);
DECLARE @DatabaseName NVARCHAR(100);
DECLARE @BackupFileName NVARCHAR(200);

-- Set variables (will be replaced by sed)
SET @BackupPath = N'BACKUP_PATH_PLACEHOLDER';
SET @DatabaseName = N'DATABASE_NAME_PLACEHOLDER';
SET @BackupFileName = N'BACKUP_FILENAME_PLACEHOLDER';

PRINT 'Database: ' + @DatabaseName;
PRINT 'Backup file: ' + @BackupFileName;
PRINT 'Full path: ' + @BackupPath;
PRINT '';

-- Check if database exists and is online
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseName AND state = 0)
BEGIN
    PRINT 'ERROR: Database does not exist or is not online!';
    RETURN;
END

-- Perform backup
BEGIN TRY
    -- Dynamic SQL for backup
    DECLARE @sql NVARCHAR(MAX);
    SET @sql = N'BACKUP DATABASE [' + @DatabaseName + '] TO DISK = N''' + @BackupPath + ''' WITH FORMAT, INIT, NAME = N''' + @DatabaseName + '-Full Database Backup'', SKIP, NOREWIND, NOUNLOAD, STATS = 10';
    
    PRINT 'Executing backup...';
    EXEC sp_executesql @sql;
    
    PRINT '';
    PRINT 'Backup completed successfully!';
    PRINT 'File: ' + @BackupFileName;
    
END TRY
BEGIN CATCH
    PRINT 'ERROR: Backup failed!';
    PRINT 'Error: ' + ERROR_MESSAGE();
    PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10));
END CATCH
SQLEOF

    # Replace placeholders using sed
    sed -i "s/BACKUP_PATH_PLACEHOLDER/${backup_path//\//\\/}/g" /tmp/backup_database.sql
    sed -i "s/DATABASE_NAME_PLACEHOLDER/$database_name/g" /tmp/backup_database.sql
    sed -i "s/BACKUP_FILENAME_PLACEHOLDER/$backup_filename/g" /tmp/backup_database.sql
}

# Function to perform backup
perform_backup() {
    local database_name="$1"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_filename="Backup_${database_name}_${timestamp}.bak"
    local backup_path="${BACKUP_DIR}/${backup_filename}"
    
    print_info "Creating backup script..."
    
    # Create backup SQL script
    create_backup_script "$database_name" "$backup_path" "$backup_filename"
    
    print_info "Copying backup script to container..."
    docker cp /tmp/backup_database.sql "$CONTAINER_NAME:/tmp/" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        print_error "Failed to copy backup script to container"
        return 1
    fi
    
    print_info "Executing backup for database: $database_name"
    echo "----------------------------------------"
    
    # Execute backup
    docker exec "$CONTAINER_NAME" /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -i /tmp/backup_database.sql
    
    local backup_result=$?
    
    # Clean up
    rm -f /tmp/backup_database.sql
    docker exec "$CONTAINER_NAME" rm -f /tmp/backup_database.sql > /dev/null 2>&1
    
    echo "----------------------------------------"
    
    if [ $backup_result -eq 0 ]; then
        print_success "Backup completed successfully!"
        print_info "Backup file: $backup_filename"
        print_info "Location: $backup_path (inside container)"
        
        # Check if backup file exists and get size
        if docker exec "$CONTAINER_NAME" test -f "$backup_path"; then
            local file_size=$(docker exec "$CONTAINER_NAME" du -h "$backup_path" 2>/dev/null | cut -f1)
            if [ ! -z "$file_size" ]; then
                print_info "File size: $file_size"
            fi
        fi
    else
        print_error "Backup failed! Please check the error messages above."
        return 1
    fi
}

# Function to show menu
show_menu() {
    echo
    echo "=============================================="
    echo "    SQL Server Database Backup Tool"
    echo "=============================================="
    echo "  Interactive Docker Container & Database"
    echo "           Backup Utility"
    echo "=============================================="
    echo
}

# Main script
main() {
    show_menu
    
    # Step 1: Select Docker container
    select_container
    
    # Step 2: Get and test SA password
    get_sa_password
    
    # Step 3: Create backup directory
    create_backup_dir
    
    # Step 4: Get list of databases
    print_info "Retrieving database list from container: $CONTAINER_NAME"
    DB_LIST=$(get_databases)
    
    if [ -z "$DB_LIST" ]; then
        print_warning "No user databases found or unable to connect to SQL Server"
        print_info "Make sure SQL Server is running and accessible in container: $CONTAINER_NAME"
        exit 1
    fi
    
    echo
    print_success "Available databases in container '$CONTAINER_NAME':"
    echo "$DB_LIST" | nl -w3 -s'. '
    echo
    
    # Step 5: Interactive database selection
    while true; do
        echo -n "Enter database name (or number from list above): "
        read -r user_input
        
        # Check if input is empty
        if [ -z "$user_input" ]; then
            print_warning "Please enter a database name or number"
            continue
        fi
        
        # Check if input is a number
        if [[ "$user_input" =~ ^[0-9]+$ ]]; then
            # User entered a number, get database name from list
            DATABASE_NAME=$(echo "$DB_LIST" | sed -n "${user_input}p")
            if [ -z "$DATABASE_NAME" ]; then
                print_error "Invalid number. Please choose a number from 1 to $(echo "$DB_LIST" | wc -l)"
                continue
            fi
        else
            # User entered database name directly
            DATABASE_NAME="$user_input"
        fi
        
        # Validate database name
        if validate_database "$DATABASE_NAME" "$DB_LIST"; then
            break
        else
            print_error "Database '$DATABASE_NAME' not found or not accessible"
            print_info "Available databases:"
            echo "$DB_LIST" | sed 's/^/  - /'
        fi
    done
    
    # Step 6: Confirmation and backup
    echo
    print_info "Backup Summary:"
    print_info "  Container: $CONTAINER_NAME"
    print_info "  Database: $DATABASE_NAME"
    print_info "  Backup Location: $BACKUP_DIR (inside container)"
    echo
    echo -n "Proceed with backup? (y/N): "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo
        perform_backup "$DATABASE_NAME"
        
        if [ $? -eq 0 ]; then
            echo
            print_success "Backup operation completed successfully!"
            echo
            print_info "To copy backup file to host system, use:"
            print_info "docker cp $CONTAINER_NAME:$BACKUP_DIR/Backup_${DATABASE_NAME}_* /your/local/path/"
            echo
            print_info "To list all backup files in container:"
            print_info "docker exec $CONTAINER_NAME ls -la $BACKUP_DIR/"
        else
            echo
            print_error "Backup operation failed!"
            exit 1
        fi
    else
        print_info "Backup cancelled by user"
    fi
}

# Run main function
main