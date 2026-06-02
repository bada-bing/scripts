#!/bin/bash

# This script processes a single document.
# Required configuration can be supplied with environment variables or a config
# file pointed to by DOCUMENT_MANAGEMENT_CONFIG.
# Required: DOCUMENT_APPROVE_DIR, DOCUMENT_QUEUE_DIR
# Optional: OCR_LANGUAGES

FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${DOCUMENT_MANAGEMENT_CONFIG:-$SCRIPT_DIR/document_management.env}"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

APPROVE_DIR="${DOCUMENT_APPROVE_DIR:-}"
LOG_DIR="${DOCUMENT_QUEUE_DIR:-}"
OCR_LANGUAGES="${OCR_LANGUAGES:-eng}"

require_config() {
    local name="$1"
    local value="$2"

    if [ -z "$value" ]; then
        echo "Error: $name is not configured"
        echo "Set it in the environment or in DOCUMENT_MANAGEMENT_CONFIG."
        exit 1
    fi
}

require_config "DOCUMENT_APPROVE_DIR" "$APPROVE_DIR"
require_config "DOCUMENT_QUEUE_DIR" "$LOG_DIR"
mkdir -p "$APPROVE_DIR" "$LOG_DIR"

# Validate input
if [ -z "$FILE" ]; then
    echo "Error: No file provided"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "Error: File does not exist: $FILE"
    exit 1
fi

FILENAME=$(basename "$FILE")
LOG_FILE="$LOG_DIR/${FILENAME}.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# PDF validation function
validate_pdf() {
    local filepath="$1"
    
    log "Validating PDF..."
    
    # Check if it's a PDF by magic number (file signature)
    if ! file "$filepath" | grep -q "PDF"; then
        log "Error: Not a valid PDF file"
        return 1
    fi
    
    # Validate PDF structure with pdfinfo
    if ! pdfinfo "$filepath" &>/dev/null; then
        log "Error: PDF is corrupted or unreadable"
        return 1
    fi
    
    # Get basic PDF info
    local page_count=$(pdfinfo "$filepath" 2>/dev/null | grep "Pages:" | awk '{print $2}')
    local file_size=$(stat -f%z "$filepath" 2>/dev/null)
    
    log "✓ Valid PDF: $page_count pages, $file_size bytes"
    
    # Check if PDF is encrypted/password protected
    if pdfinfo "$filepath" 2>/dev/null | grep -q "Encrypted:.*yes"; then
        log "Warning: PDF is encrypted/password protected"
        return 2  # Different return code for encrypted files
    fi
    
    return 0
}

# OCR processing function
process_ocr() {
    local input_file="$1"
    local output_file="$2"
    
    log "Processing PDF with intelligent OCR..."
    log "(Pages with existing text will be preserved, pages without text will be OCRed)"
    
    # Always run with --skip-text to handle any mixed content
    # This ensures every page gets processed appropriately
    if ocrmypdf \
        --rotate-pages \
        --deskew \
        --clean \
        --optimize 1 \
        --output-type pdfa-2 \
        --language "$OCR_LANGUAGES" \
        --skip-text \
        "$input_file" "$output_file" 2>&1 | tee -a "$LOG_FILE"; then
        
        local text_content=$(pdftotext "$output_file" - 2>/dev/null | tr -d '[:space:]' | wc -c)
        log "✓ Processing completed successfully (${text_content} characters total)"
        return 0
    else
        log "Error: OCR processing failed"
        return 1
    fi
}

# Extract metadata and generate filename
generate_filename() {
    local filepath="$1"
    local original_filename="$2"
    
    # Log to file only (not stdout) during filename generation
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Extracting metadata for filename generation..." >> "$LOG_FILE"
    
    # Extract text from PDF
    local text=$(pdftotext "$filepath" - 2>/dev/null | head -100)
    
    # Initialize components
    local year="xxxx"
    local month=""
    local day=""
    local correspondent=""
    local description=""
    
    # ============================================
    # Extract Date
    # ============================================
    # Try DD.MM.YYYY format (German style)
    local date_match=$(echo "$text" | grep -oE '[0-9]{2}\.[0-9]{2}\.[0-9]{4}' | head -1)
    
    if [ -n "$date_match" ]; then
        day=$(echo "$date_match" | cut -d'.' -f1)
        month=$(echo "$date_match" | cut -d'.' -f2)
        year=$(echo "$date_match" | cut -d'.' -f3)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found date: $date_match → ${year}_${month}-${day}" >> "$LOG_FILE"
    else
        # Try YYYY-MM-DD format
        date_match=$(echo "$text" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
        if [ -n "$date_match" ]; then
            year=$(echo "$date_match" | cut -d'-' -f1)
            month=$(echo "$date_match" | cut -d'-' -f2)
            day=$(echo "$date_match" | cut -d'-' -f3)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found date: $date_match → ${year}_${month}-${day}" >> "$LOG_FILE"
        else
            # Try to find just year
            year_match=$(echo "$text" | grep -oE '20[0-9]{2}' | head -1)
            if [ -n "$year_match" ]; then
                year="$year_match"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found only year: $year" >> "$LOG_FILE"
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] No date found, using xxxx" >> "$LOG_FILE"
            fi
        fi
    fi
    
    # ============================================
    # Extract Correspondent (Company/Person Name)
    # ============================================
    local first_lines=$(echo "$text" | head -10)
    
    # Look for company name (line with GmbH, AG, e.V., etc.)
    if echo "$first_lines" | grep -qiE '(GmbH|AG|e\.V\.|Inc|Ltd|Corp)'; then
        # Extract the line with company indicator
        local company_line=$(echo "$first_lines" | grep -iE '(GmbH|AG|e\.V\.|Inc|Ltd|Corp)' | head -1)
        
        # Try to extract just the main company name (first few words before GmbH/AG/etc)
        correspondent=$(echo "$company_line" | sed -E 's/(GmbH|AG|e\.V\.|Inc|Ltd|Corp).*/\1/' | awk '{print $1, $2}' | tr -d '\n' | sed 's/[^a-zA-Z0-9]/_/g' | tr '[:lower:]' '[:upper:]' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
    else
        # Use first non-empty line, but extract just first 2-3 words
        correspondent=$(echo "$first_lines" | grep -v '^[[:space:]]*$' | head -1 | awk '{print $1, $2}' | tr -d '\n' | sed 's/[^a-zA-Z0-9]/_/g' | tr '[:lower:]' '[:upper:]' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
    fi
    
    # Limit correspondent length to 15 characters max
    correspondent=$(echo "$correspondent" | cut -c1-15)
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Correspondent: $correspondent" >> "$LOG_FILE"
    
    # ============================================
    # Generate Description
    # ============================================
    if echo "$text" | grep -qiE 'rechnung|invoice'; then
        description="bill"
    elif echo "$text" | grep -qiE 'vertrag|contract'; then
        description="contract"
    elif echo "$text" | grep -qiE 'quittung|receipt'; then
        description="receipt"
    elif echo "$text" | grep -qiE 'mahnung|reminder'; then
        description="reminder"
    elif echo "$text" | grep -qiE 'bestellung|order'; then
        description="order"
    elif echo "$text" | grep -qiE 'angebot|offer|quote'; then
        description="offer"
    else
        # Use part of original filename as fallback
        description=$(echo "$original_filename" | sed 's/\.pdf$//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | cut -c1-15)
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Description: $description" >> "$LOG_FILE"
    
    # ============================================
    # Build Filename
    # ============================================
    local new_filename=""
    
    # Date component (use day only if it adds useful info)
    if [ -n "$month" ]; then
        new_filename="${year}_${month}"
    else
        new_filename="${year}"
    fi
    
    # Add correspondent if found
    if [ -n "$correspondent" ]; then
        new_filename="${new_filename}-${correspondent}"
    fi
    
    # Add description
    new_filename="${new_filename}-${description}.pdf"
    
    # Clean up any double separators
    new_filename=$(echo "$new_filename" | sed 's/--*/-/g' | sed 's/__*/_/g')
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Generated filename: $new_filename" >> "$LOG_FILE"
    
    # Output ONLY the filename (no log messages to stdout)
    echo "$new_filename"
}

# Start processing
log "Started processing: $FILENAME"

# ============================================
# Step 1: Validate PDF
# ============================================
validate_pdf "$FILE"
validation_result=$?

if [ $validation_result -eq 1 ]; then
    log "Validation failed. Aborting."
    exit 1
elif [ $validation_result -eq 2 ]; then
    log "PDF is encrypted. Aborting."
    exit 2
fi

# ============================================
# Step 2: OCR Processing
# ============================================
# Create temp file in the approve directory with SHORT name
TEMP_OUTPUT="$APPROVE_DIR/.tmp_$$.pdf"

process_ocr "$FILE" "$TEMP_OUTPUT"
ocr_result=$?

if [ $ocr_result -ne 0 ]; then
    log "OCR processing failed. Aborting."
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# ============================================
# Step 3: Generate intelligent filename
# ============================================
NEW_FILENAME=$(generate_filename "$TEMP_OUTPUT" "$FILENAME")
DEST="$APPROVE_DIR/$NEW_FILENAME"

# Check if file already exists, add counter if needed
if [ -f "$DEST" ]; then
    counter=1
    base_name="${NEW_FILENAME%.pdf}"
    while [ -f "$APPROVE_DIR/${base_name}_${counter}.pdf" ]; do
        ((counter++))
    done
    DEST="$APPROVE_DIR/${base_name}_${counter}.pdf"
    log "File exists, using: ${base_name}_${counter}.pdf"
fi

# ============================================
# Step 4: Finalize - rename temp to final
# ============================================
mv "$TEMP_OUTPUT" "$DEST"

if [ $? -eq 0 ]; then
    log "✓ Completed processing: $FILENAME"
    log "✓ Saved as: $(basename "$DEST")"
    
    # Delete original file from inbox
    rm -f "$FILE"
    log "✓ Removed original from inbox"
else
    log "Error: Failed to finalize processed file"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

exit 0
