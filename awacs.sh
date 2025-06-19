#!/bin/bash
# ===================================================
# AWACS - Advanced WiFi Auto Connection System
# أواكس - أنظمة واي فاي التلقائية كاملة السيطرة
# VER 1.0 (Ultra-Stable)
# ===================================================
#
#     █████╗ ██╗    ██╗ █████╗  ██████╗███████╗
#    ██╔══██╗██║    ██║██╔══██╗██╔════╝██╔════╝
#    ███████║██║ █╗ ██║███████║██║     ███████╗
#    ██╔══██║██║███╗██║██╔══██║██║     ╚════██║
#    ██║  ██║╚███╔███╔╝██║  ██║╚██████╗███████║
#    ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝
#
#            🛡️ Always Watching, Always Connected 🛡️
#            🛡️ مراقبة دائمة، اتصال مستمر 🛡️
#
# ===================================================
# Created by: NetStorm - AbuNaif (hmne)
# GitHub: https://github.com/hmne/awacs
# بواسطة: نت ستورم - أبونايف (محمد المطيري)
# ===================================================
#
# AWACS Definition - تعريف أواكس:
# 🔹 Advanced    - متقدم      : Sophisticated algorithms
# 🔹 WiFi        - واي فاي    : Wireless network management  
# 🔹 Auto        - تلقائي     : Autonomous operation
# 🔹 Connection  - اتصال      : Network connectivity
# 🔹 System      - نظام       : Complete solution
#
# Military AWACS aircraft provide continuous surveillance
# and control of airspace. Similarly, this AWACS ensures
# uninterrupted WiFi connectivity through intelligent
# monitoring and automatic network management.
#
# طائرات الإنذار المبكر العسكرية توفر مراقبة وتحكم مستمر
# للمجال الجوي. بالمثل، هذا الأواكس يضمن اتصال واي فاي
# متواصل من خلال المراقبة الذكية والإدارة التلقائية للشبكة.
# ===================================================

# ========================================
# USER CONFIGURATION - إعدادات المستخدم
# ========================================

# LANGUAGE SETTINGS | إعدادات اللغة
# Choose your preferred language:
# اختر لغتك المفضلة:
# "en" = English only | إنجليزي فقط
# "ar" = Arabic only | عربي فقط
# "both" = Bilingual (English + Arabic) | ثنائي اللغة (إنجليزي + عربي)
LANGUAGE="both"

# LOGGING PREFERENCES | تفضيلات التسجيل
# Choose how to save logs:
# اختر كيفية حفظ السجلات:
# "local" = Save logs locally only | حفظ السجلات محلياً فقط
# "remote" = Send logs to remote server only | إرسال السجلات للخادم البعيد فقط
# "both" = Local + Remote logging | تسجيل محلي + بعيد
# "none" = No logging (not recommended) | بدون تسجيل (غير مستحسن)
LOG_MODE="local"

# REMOTE LOGGING CONFIGURATION | تكوين التسجيل البعيد
# Enable remote logging? | تفعيل التسجيل البعيد؟
REMOTE_LOGGING="no"              # "yes" to enable | "yes" للتفعيل

# Remote server URL (configure only if REMOTE_LOGGING="yes")
# رابط الخادم البعيد (اضبط فقط إذا كان REMOTE_LOGGING="yes")
REMOTE_URL=""                    # Example: "http://your-server.com/awacs"

# DEVICE CONFIGURATION | تكوين الجهاز
DEVICE_ID="AWACS-1"              # Unique device identifier | معرف جهاز فريد
DEVICE_NAME="AWACS WiFi Manager" # Device display name | اسم عرض الجهاز

# ========================================
# CUSTOM PATHS CONFIGURATION | تكوين المسارات المخصصة
# ========================================

# Custom directory paths (leave empty to use default beside script)
# مسارات مجلدات مخصصة (اتركها فارغة لاستخدام الافتراضي جانب السكريبت)

CUSTOM_WORK_DIR=""               # Custom work directory | مجلد العمل المخصص
                                 # Example: "/home/user/awacs" | مثال: "/home/user/awacs"
                                 # Leave empty for default: script_dir/test | اتركه فارغ للافتراضي

CUSTOM_LOG_DIR=""                # Custom log directory | مجلد السجلات المخصص
                                 # Example: "/var/log/awacs" | مثال: "/var/log/awacs"
                                 # Leave empty for default: work_dir/logs | اتركه فارغ للافتراضي

CUSTOM_TEMP_DIR=""               # Custom temp directory | مجلد الملفات المؤقتة المخصص
                                 # Example: "/tmp/awacs" | مثال: "/tmp/awacs"
                                 # Leave empty for default: work_dir/temp | اتركه فارغ للافتراضي

CUSTOM_CONFIG_DIR=""             # Custom config directory | مجلد التكوين المخصص
                                 # Example: "/etc/awacs" | مثال: "/etc/awacs"
                                 # Leave empty for default: work_dir/config | اتركه فارغ للافتراضي

# ========================================
# DEFAULT DIRECTORY NAME | اسم المجلد الافتراضي
# ========================================

DEFAULT_DIR_NAME="awacs"         # Default directory name beside script | اسم المجلد الافتراضي جانب السكريبت
                                 # Example: "awacs", "wifi-manager", "my-awacs" | مثال: "awacs", "wifi-manager", "my-awacs"
                                 # This creates: script_dir/awacs/ | هذا ينشئ: script_dir/awacs/

# ========================================
# DIRECTORY STRUCTURE - هيكل المجلدات
# ========================================

# Get script directory | الحصول على مجلد السكريبت
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ========================================
# SMART PATH RESOLUTION | حل المسارات الذكي
# ========================================

# Function to validate and set custom paths | دالة للتحقق من وتعيين المسارات المخصصة
setup_custom_paths() {
    local errors=()
    
    # Work directory setup | إعداد مجلد العمل
    if [[ -n "$CUSTOM_WORK_DIR" ]]; then
        # Use custom work directory | استخدام مجلد العمل المخصص
        WORK_DIR="$(realpath "$CUSTOM_WORK_DIR" 2>/dev/null || echo "$CUSTOM_WORK_DIR")"
        echo "ℹ️  Using custom work directory: $WORK_DIR"
        echo "ℹ️  استخدام مجلد عمل مخصص: $WORK_DIR"
    else
        # Default: beside script | الافتراضي: جانب السكريبت
        WORK_DIR="$SCRIPT_DIR/$DEFAULT_DIR_NAME"
    fi
    
    # Log directory setup | إعداد مجلد السجلات
    if [[ -n "$CUSTOM_LOG_DIR" ]]; then
        LOG_DIR="$(realpath "$CUSTOM_LOG_DIR" 2>/dev/null || echo "$CUSTOM_LOG_DIR")"
        echo "ℹ️  Using custom log directory: $LOG_DIR"
        echo "ℹ️  استخدام مجلد سجلات مخصص: $LOG_DIR"
    else
        LOG_DIR="$WORK_DIR/logs"
    fi
    
    # Temp directory setup | إعداد مجلد الملفات المؤقتة
    if [[ -n "$CUSTOM_TEMP_DIR" ]]; then
        TEMP_WIFI_DIR="$(realpath "$CUSTOM_TEMP_DIR" 2>/dev/null || echo "$CUSTOM_TEMP_DIR")"
        echo "ℹ️  Using custom temp directory: $TEMP_WIFI_DIR"
        echo "ℹ️  استخدام مجلد ملفات مؤقتة مخصص: $TEMP_WIFI_DIR"
    else
        TEMP_WIFI_DIR="$WORK_DIR/temp"
    fi
    
    # Config directory setup | إعداد مجلد التكوين
    if [[ -n "$CUSTOM_CONFIG_DIR" ]]; then
        CONFIG_DIR="$(realpath "$CUSTOM_CONFIG_DIR" 2>/dev/null || echo "$CUSTOM_CONFIG_DIR")"
        echo "ℹ️  Using custom config directory: $CONFIG_DIR"
        echo "ℹ️  استخدام مجلد تكوين مخصص: $CONFIG_DIR"
    else
        CONFIG_DIR="$WORK_DIR/config"
    fi
    
    # Validate all paths | التحقق من صحة جميع المسارات
    local all_dirs=("$WORK_DIR" "$LOG_DIR" "$TEMP_WIFI_DIR" "$CONFIG_DIR")
    
    for dir in "${all_dirs[@]}"; do
        # Check if parent directory exists or can be created | فحص إذا كان المجلد الأب موجود أو يمكن إنشاؤه
        local parent_dir="$(dirname "$dir")"
        if [[ ! -d "$parent_dir" ]] && ! mkdir -p "$parent_dir" 2>/dev/null; then
            errors+=("Cannot create parent directory for: $dir")
            continue
        fi
        
        # Try to create the directory | محاولة إنشاء المجلد
        if ! mkdir -p "$dir" 2>/dev/null; then
            errors+=("Cannot create directory: $dir")
            continue
        fi
        
        # Check write permissions | فحص صلاحيات الكتابة
        if [[ ! -w "$dir" ]]; then
            errors+=("No write permission for directory: $dir")
        fi
    done
    
    # Report errors if any | الإبلاغ عن الأخطاء إن وجدت
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "❌ Path setup errors | أخطاء في إعداد المسارات:"
        for error in "${errors[@]}"; do
            echo "   • $error"
        done
        echo ""
        echo "💡 Falling back to default paths beside script"
        echo "💡 العودة للمسارات الافتراضية جانب السكريبت"
        
        # Fallback to default paths | العودة للمسارات الافتراضية
        WORK_DIR="$SCRIPT_DIR/$DEFAULT_DIR_NAME"
        LOG_DIR="$WORK_DIR/logs"
        TEMP_WIFI_DIR="$WORK_DIR/temp"
        CONFIG_DIR="$WORK_DIR/config"
        
        # Create default directories | إنشاء المجلدات الافتراضية
        mkdir -p "$WORK_DIR" "$LOG_DIR" "$TEMP_WIFI_DIR" "$CONFIG_DIR"
    fi
}

# Setup paths | إعداد المسارات
setup_custom_paths

# Final file paths | مسارات الملفات النهائية
LOG_FILE="$LOG_DIR/awacs.log"                # Main log file | ملف السجل الرئيسي

# System files in local directory | ملفات النظام في المجلد المحلي
PIDFILE="$TEMP_WIFI_DIR/awacs.pid"           # Process ID file | ملف معرف العملية
REMOTE_LOG_FILE="$TEMP_WIFI_DIR/failed_remote_logs.txt"  # Failed remote logs | السجلات البعيدة الفاشلة
LOCK_FILE="$TEMP_WIFI_DIR/awacs.lock"       # Process lock file | ملف قفل العملية
LAST_SUCCESSFUL_SSID_FILE="$TEMP_WIFI_DIR/last_success.txt"  # Last successful SSID | آخر SSID ناجح
LAST_SCAN_FILE="$TEMP_WIFI_DIR/last_scan.txt"              # Last scan results | نتائج آخر فحص
SCAN_OUTPUT_TMP="$TEMP_WIFI_DIR/scan_output.tmp"           # Temporary scan output | مخرجات الفحص المؤقتة
TEMP_WIFI_FILE="$TEMP_WIFI_DIR/open_networks.conf"         # Open networks config | تكوين الشبكات المفتوحة

# Set up remote logging URL if enabled | إعداد رابط التسجيل البعيد إذا كان مفعلاً
if [[ "$REMOTE_LOGGING" == "yes" && -n "$REMOTE_URL" ]]; then
    URL_PATH="awacs"
    URL="$REMOTE_URL"
    log="$URL/log/write_file_.php"
else
    URL_PATH=""
    URL=""
    log=""
fi

# ========================================
# PERFORMANCE & TIMING SETTINGS
# ========================================

# Timing Configuration - يتم تعديلها حسب SPEED_MODE
CHECK_INTERVAL=5
SWITCH_TIMEOUT=4
MAX_FAILURES=3
MIN_SPEED=1.5
CRITICAL_SPEED=0.1

# Advanced Options - يتم تعديلها حسب SPEED_MODE
CONSERVE_RESOURCES="yes"
SCAN_INTERVAL=30
PRE_SCAN_SLEEP=2

# ========================================
# FEATURE CONFIGURATION
# ========================================

# Network Connection Features
AUTO_CONNECT_OPEN="no"
CONNECT_HIDDEN="yes"

# Night Mode Settings
NIGHT_MODE="no"
NIGHT_START="22:00"
NIGHT_END="06:00"
NIGHT_CHECK_INTERVAL=15
ORIGINAL_CHECK_INTERVAL=$CHECK_INTERVAL
ORIGINAL_MIN_SPEED=$MIN_SPEED

# Security Features
STEALTH_MODE="no"

# System Mode Settings
DEBUG_MODE="no"
TEST_MODE="no"
SYSTEM_BOOTING=true

# ========================================
# ADAPTIVE SPEED MODE CONFIGURATION
# ========================================

# Speed Mode Selection - يتوازن بين السرعة والاستقرار
# "conservative" = مستقر لكن بطيء (155 ثانية)
# "balanced" = متوازن (90 ثانية) - DEFAULT
# "fast" = سريع لكن أقل استقرار (60 ثانية)
SPEED_MODE="balanced"

# ========================================
# ADVANCED HARDWARE & NETWORK SETTINGS
# ========================================

# Hardware Configuration
HARDWARE_CHECK="yes"
MULTI_INTERFACE="yes"
READ_ONLY_WPA="yes"

# Network Management Limits
MAX_NETWORK_SIZE=30
MAX_TEMP_NETWORKS=15

# Speed Thresholds
SPEED_THRESHOLD=1.5
NEVER_BREAK_THRESHOLD=1.2

# ========================================
# RUNTIME STATE VARIABLES
# ========================================

# WiFi Interface and Connection State
WIFI_INTERFACE=""
INTERNET_CONNECTED=false
LAST_SUCCESSFUL_SSID=""

# Caching for Performance
CURRENT_SSID_CACHE=""
CURRENT_SSID_CACHE_TIME=0
CACHE_VALIDITY_SECONDS=3
LAST_SCAN_TIME=0

# Adaptive Algorithm Variables
CONSECUTIVE_STABLE_CONNECTIONS=0
ADAPTIVE_SCAN_INTERVAL=$SCAN_INTERVAL
MIN_SCAN_INTERVAL=15
MAX_SCAN_INTERVAL=120

# Debug and Logging State
# (CURRENT_DEBUG_LOG removed as unused)

# ========================================
# NETWORK ARRAYS & COMPLEX CONFIGURATIONS
# ========================================

# Emergency Networks Configuration
USE_SAFETY_NET="yes"
declare -A SAFETY_NET=(
    # ["SSID"]="PASSWORD"    # أضف شبكات الطوارئ هنا
)

# DNS Servers Configuration - إصلاح مشكلة DNS hijacking
PRIMARY_DNS_SERVERS=(
    "8.8.8.8"
    "1.1.1.1" 
    "208.67.222.222"
)

FALLBACK_DNS_SERVERS=(
    "9.9.9.9"
    "77.88.8.8"
    "8.26.56.26"
)

# Speed Test Servers - محسّنة مع خوادم إضافية
SPEED_TEST_METHOD="auto"
SPEEDTEST_SERVERS=(
    "https://speed.cloudflare.com/__down?bytes=500000"
    "http://speedtest.ftp.otenet.gr/files/test100k.db"
    "https://speedtest.ae.rt.ru/upload"
    "http://speedtest.wdc01.softlayer.com/downloads/test10.zip"
    "https://proof.ovh.net/files/1Mb.dat"
)

# Network Scoring Configuration
declare -A SCORE_WEIGHTS=(
    ["speed"]=70
    ["signal"]=20
    ["priority"]=10
)

# ========================================
# ALGORITHM STATE VARIABLES
# ========================================

# Speed Fluctuation Tracking
LOW_SPEED_COUNT=0
LOW_SPEED_THRESHOLD=3

# ========================================
# COMMAND LINE PROCESSING - معالجة سطر الأوامر
# ========================================

# Default command line state | حالة سطر الأوامر الافتراضية
DAEMON_MODE=false
VERBOSE=true

# Parse command line arguments | تحليل معلمات سطر الأوامر
while [[ $# -gt 0 ]]; do
    case "$1" in
        # System Control Options | خيارات تحكم النظام
        -d|--daemon)
            DAEMON_MODE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            VERBOSE=false
            shift
            ;;
            
        # Performance Mode Options | خيارات وضع الأداء
        --performance|--fast)
            SPEED_MODE="fast"
            shift
            ;;
        --balanced)
            SPEED_MODE="balanced"
            shift
            ;;
        --stability|--conservative)
            SPEED_MODE="conservative"
            shift
            ;;
            
        # Language Options | خيارات اللغة
        --lang-en)
            LANGUAGE="en"
            shift
            ;;
        --lang-ar)
            LANGUAGE="ar"
            shift
            ;;
        --lang-both)
            LANGUAGE="both"
            shift
            ;;
            
        # Logging Options | خيارات التسجيل
        --log-local)
            LOG_MODE="local"
            shift
            ;;
        --log-remote)
            LOG_MODE="remote"
            REMOTE_LOGGING="yes"
            shift
            ;;
        --log-both)
            LOG_MODE="both"
            REMOTE_LOGGING="yes"
            shift
            ;;
        --log-none)
            LOG_MODE="none"
            shift
            ;;
            
        *)
            break
            ;;
    esac
done

# دالة تكوين إعدادات السرعة والاستقرار
configure_speed_mode() {
    case "$SPEED_MODE" in
        "fast")
            # سريع - 60 ثانية للريبوت (أقل استقرار)
            CHECK_INTERVAL=3
            SWITCH_TIMEOUT=2
            MAX_FAILURES=2
            SCAN_INTERVAL=10
            PRE_SCAN_SLEEP=1
            CONSERVE_RESOURCES="no"
            # سيتم إعلام المستخدم لاحقاً في main()
            ;;
        "balanced")
            # متوازن - 90 ثانية للريبوت (توازن جيد)
            CHECK_INTERVAL=4
            SWITCH_TIMEOUT=3
            MAX_FAILURES=2
            SCAN_INTERVAL=20
            PRE_SCAN_SLEEP=1
            CONSERVE_RESOURCES="yes"
            # سيتم إعلام المستخدم لاحقاً في main()
            ;;
        "conservative")
            # محافظ - 155 ثانية للريبوت (أقصى استقرار)
            CHECK_INTERVAL=5
            SWITCH_TIMEOUT=4
            MAX_FAILURES=3
            SCAN_INTERVAL=30
            PRE_SCAN_SLEEP=2
            CONSERVE_RESOURCES="yes"
            # سيتم إعلام المستخدم لاحقاً في main()
            ;;
        *)
            # سيتم التحذير لاحقاً في main()
            SPEED_MODE="balanced"
            # Note: Will reconfigure with balanced mode (no recursion)
            ;;
    esac
}

# تأكد من وجود المجلد المؤقت
mkdir -p "$TEMP_WIFI_DIR"

# تكوين إعدادات السرعة
configure_speed_mode

# ========================================
# CONFIGURATION VALIDATION - التحقق من صحة التكوين
# ========================================

validate_configuration() {
    local errors=()
    local warnings=()
    
    log_message "DEBUG" "Starting configuration validation" "بدء التحقق من صحة التكوين"
    
    # التحقق من SPEED_MODE
    if [[ ! "$SPEED_MODE" =~ ^(fast|balanced|conservative)$ ]]; then
        errors+=("Invalid SPEED_MODE: '$SPEED_MODE'. Must be: fast, balanced, or conservative")
        SPEED_MODE="balanced"
        warnings+=("SPEED_MODE reset to 'balanced'")
    fi
    
    # التحقق من LANGUAGE
    if [[ ! "$LANGUAGE" =~ ^(en|ar|both)$ ]]; then
        errors+=("Invalid LANGUAGE: '$LANGUAGE'. Must be: en, ar, or both")
        LANGUAGE="both"
        warnings+=("LANGUAGE reset to 'both'")
    fi
    
    # التحقق من LOG_MODE
    if [[ ! "$LOG_MODE" =~ ^(local|remote|both|none)$ ]]; then
        errors+=("Invalid LOG_MODE: '$LOG_MODE'. Must be: local, remote, both, or none")
        LOG_MODE="local"
        warnings+=("LOG_MODE reset to 'local'")
    fi
    
    # التحقق من CHECK_INTERVAL
    if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] || ((CHECK_INTERVAL < 1 || CHECK_INTERVAL > 300)); then
        errors+=("Invalid CHECK_INTERVAL: '$CHECK_INTERVAL'. Must be between 1-300 seconds")
        CHECK_INTERVAL=5
        warnings+=("CHECK_INTERVAL reset to 5")
    fi
    
    # التحقق من SWITCH_TIMEOUT
    if ! [[ "$SWITCH_TIMEOUT" =~ ^[0-9]+$ ]] || ((SWITCH_TIMEOUT < 1 || SWITCH_TIMEOUT > 30)); then
        errors+=("Invalid SWITCH_TIMEOUT: '$SWITCH_TIMEOUT'. Must be between 1-30 seconds")
        SWITCH_TIMEOUT=4
        warnings+=("SWITCH_TIMEOUT reset to 4")
    fi
    
    # التحقق من MAX_FAILURES
    if ! [[ "$MAX_FAILURES" =~ ^[0-9]+$ ]] || ((MAX_FAILURES < 1 || MAX_FAILURES > 10)); then
        errors+=("Invalid MAX_FAILURES: '$MAX_FAILURES'. Must be between 1-10")
        MAX_FAILURES=3
        warnings+=("MAX_FAILURES reset to 3")
    fi
    
    # التحقق من DEVICE_ID
    if [[ -z "$DEVICE_ID" || ${#DEVICE_ID} -lt 3 || ${#DEVICE_ID} -gt 32 ]]; then
        errors+=("Invalid DEVICE_ID: '$DEVICE_ID'. Must be 3-32 characters")
        DEVICE_ID="AWACS-$(date +%s | tail -c 4)"
        warnings+=("DEVICE_ID reset to '$DEVICE_ID'")
    fi
    
    # التحقق من PRIMARY_DNS_SERVERS
    if [[ ${#PRIMARY_DNS_SERVERS[@]} -eq 0 ]]; then
        errors+=("No PRIMARY_DNS_SERVERS defined")
        PRIMARY_DNS_SERVERS=("8.8.8.8" "1.1.1.1")
        warnings+=("PRIMARY_DNS_SERVERS set to default Google/Cloudflare DNS")
    else
        for dns in "${PRIMARY_DNS_SERVERS[@]}"; do
            if ! [[ "$dns" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                errors+=("Invalid DNS server format: '$dns'")
            else
                # التحقق من صحة كل جزء من IP
                local IFS='.'
                local ip_parts=($dns)
                for part in "${ip_parts[@]}"; do
                    if ((part < 0 || part > 255)); then
                        errors+=("Invalid DNS server IP range: '$dns'")
                        break
                    fi
                done
            fi
        done
    fi
    
    # التحقق من REMOTE_URL إذا كان التسجيل البعيد مفعل
    if [[ "$LOG_MODE" =~ (remote|both) || "$REMOTE_LOGGING" == "yes" ]]; then
        if [[ -z "$REMOTE_URL" ]]; then
            errors+=("REMOTE_URL is required when remote logging is enabled")
            LOG_MODE="local"
            REMOTE_LOGGING="no"
            warnings+=("Remote logging disabled due to missing REMOTE_URL")
        elif ! [[ "$REMOTE_URL" =~ ^https?:// ]]; then
            errors+=("Invalid REMOTE_URL format: '$REMOTE_URL'. Must start with http:// or https://")
            LOG_MODE="local"
            REMOTE_LOGGING="no"
            warnings+=("Remote logging disabled due to invalid REMOTE_URL")
        fi
    fi
    
    # التحقق من ملفات وأدلة النظام
    if [[ ! -d "$WORK_DIR" ]]; then
        if ! mkdir -p "$WORK_DIR" 2>/dev/null; then
            errors+=("Cannot create work directory: '$WORK_DIR'")
        fi
    fi
    
    if [[ ! -w "$WORK_DIR" ]]; then
        errors+=("Work directory not writable: '$WORK_DIR'")
    fi
    
    # التحقق من الأدوات المطلوبة
    local required_tools=("iwconfig" "iwlist" "wpa_cli" "ping" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            errors+=("Required tool missing: '$tool'")
        fi
    done
    
    # التحقق من صلاحيات sudo
    if ! sudo -n true 2>/dev/null; then
        warnings+=("sudo access may be required for some operations")
    fi
    
    # طباعة النتائج
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_message "ERROR" "Configuration validation failed with ${#errors[@]} errors:" "فشل التحقق من التكوين مع ${#errors[@]} أخطاء:"
        for error in "${errors[@]}"; do
            log_message "ERROR" "  - $error" "  - $error"
        done
    fi
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_message "WARN" "Configuration validation found ${#warnings[@]} warnings:" "التحقق من التكوين وجد ${#warnings[@]} تحذيرات:"
        for warning in "${warnings[@]}"; do
            log_message "WARN" "  - $warning" "  - $warning"
        done
    fi
    
    if [[ ${#errors[@]} -eq 0 && ${#warnings[@]} -eq 0 ]]; then
        log_message "SUCCESS" "Configuration validation passed" "نجح التحقق من صحة التكوين"
        return 0
    elif [[ ${#errors[@]} -eq 0 ]]; then
        log_message "INFO" "Configuration validation completed with warnings only" "اكتمل التحقق من التكوين مع تحذيرات فقط"
        return 0
    else
        log_message "ERROR" "Configuration validation failed" "فشل التحقق من صحة التكوين"
        return 1
    fi
}

# ملاحظة: سيتم تشغيل التحقق من صحة التكوين في الدالة الرئيسية
# validate_configuration سيتم استدعاؤها بعد تعريف log_message

# تشغيل في الخلفية إذا كان مطلوباً
if $DAEMON_MODE; then
    echo $$ > "$PIDFILE"
    exec 1>> "$LOG_FILE" 2>&1
    
    if [ -z "$ALREADY_DAEMONIZED" ]; then
        export ALREADY_DAEMONIZED=true
        exec setsid "$0" "$@" &
        exit 0
    fi
fi

# التحقق المبدئي من الصلاحيات
if [[ $EUID -ne 0 ]]; then
    echo
    echo -e "\033[1;37m┌─────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;37m│\033[1;41m ROOT ACCESS REQUIRED | مطلوب صلاحيات الجذر  \033[0;37m│\033[0m"
    echo -e "\033[1;37m├─────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;33m⚠️  EN: \033[0mThis script needs root privileges   \033[1;37m │\033[0m"
    echo -e "\033[1;37m│ \033[1;33m⚠️  AR: \033[0mيجب تشغيل هذا السكربت بصلاحيات الجذر \033[1;37m│\033[0m"
    echo -e "\033[1;37m├─────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;32m✓  \033[0mRun: \033[1;36msudo bash $0\033[1;37m    │\033[0m"
    echo -e "\033[1;37m└─────────────────────────────────────────────┘\033[0m"
    echo
    exit 1
fi

# --------------------------
# معالج الإشارات المحسن
# --------------------------

# دالة التنظيف المحسنة
cleanup_and_exit() {
    local exit_code=${1:-0}
    local signal_name=${2:-"MANUAL"}
    
    echo
    echo -e "\033[1;37m┌─────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;37m│\033[1;44m    GRACEFUL SHUTDOWN | إيقاف تشغيل سلس      \033[0;37m│\033[0m"
    echo -e "\033[1;37m├─────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;33m⚠️  Signal: \033[0m$signal_name received                \033[1;37m │\033[0m"
    echo -e "\033[1;37m│ \033[1;33m⚠️  إشارة: \033[0m$signal_name تم استلامها               \033[1;37m│\033[0m"
    echo -e "\033[1;37m├─────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;32m✓  \033[0mExiting gracefully | جاري الخروج بأمان \033[1;37m │\033[0m"
    echo -e "\033[1;37m└─────────────────────────────────────────────┘\033[0m"
    echo
    
    # تنظيف الملفات بشكل آمن
    [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE" 2>/dev/null
    [[ -f "$PIDFILE" ]] && rm -f "$PIDFILE" 2>/dev/null
    [[ -f "$SCAN_OUTPUT_TMP" ]] && rm -f "$SCAN_OUTPUT_TMP" 2>/dev/null
    
    exit $exit_code
}

# معالجات إشارات محسنة لتجنب الحلقات اللا نهائية
trap 'cleanup_and_exit 130 "SIGINT"' INT
trap 'cleanup_and_exit 143 "SIGTERM"' TERM
trap 'cleanup_and_exit 1 "SIGQUIT"' QUIT
trap 'cleanup_and_exit 129 "SIGHUP"' HUP
trap 'cleanup_and_exit 0 "EXIT"' EXIT

# دالة للخروج عند وجود نسخة أخرى
exit_instance_error() {
    local running_pid="$1"
    echo
    echo -e "\033[1;37m┌──────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;37m│\033[1;43m      INSTANCE ERROR | خطأ في تعدد النسخ      \033[0;37m│\033[0m"
    echo -e "\033[1;37m├──────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;31m✗  EN: \033[0mAnother instance is already running \033[1;37m  │\033[0m"
    echo -e "\033[1;37m│ \033[1;31m✗  AR: \033[0mهناك نسخة أخرى قيد التشغيل بالفعل    \033[1;37m │\033[0m"
    echo -e "\033[1;37m├──────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;36mℹ \033[0mPID: $running_pid | معرف العملية         \033[1;37m│\033[0m"
    echo -e "\033[1;37m└──────────────────────────────────────────────┘\033[0m"
    echo
    
    trap - EXIT INT TERM QUIT HUP
    exit 1
}

# ========================================
# BASIC UTILITY FUNCTIONS - الدوال الأساسية
# ========================================
# يجب أن تكون هذه الدوال في المقدمة لأنها تُستخدم في الدوال الأخرى

# دالة التسجيل الأساسية - CRITICAL: يجب أن تكون أولاً
log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local level=$1
    local eng_msg=$2
    local ar_msg=${3:-$eng_msg}

    local log_level log_color
    case $level in
        "ERROR")
            log_level="[ERROR]"
            log_color="\033[1;31m"
            ;;
        "WARN")
            log_level="[WARN]"
            log_color="\033[1;33m"
            ;;
        "INFO")
            log_level="[INFO]"
            log_color="\033[1;36m"
            ;;
        "SUCCESS")
            log_level="[SUCCESS]"
            log_color="\033[1;32m"
            level="INFO"
            ;;
        "DEBUG")
            log_level="[DEBUG]"
            log_color="\033[1;35m"
            
            if [[ "$DEBUG_MODE" != "yes" ]]; then
                return 0
            fi
            ;;
        *)
            log_level="[INFO]"
            log_color="\033[1;36m"
            level="INFO"
            ;;
    esac

    # Format message based on language preference | تنسيق الرسالة حسب تفضيل اللغة
    local final_msg=""
    case "$LANGUAGE" in
        "en")
            final_msg="$eng_msg"
            ;;
        "ar")
            final_msg="$ar_msg"
            ;;
        "both")
            if [[ "$ar_msg" != "$eng_msg" ]]; then
                final_msg="$eng_msg | $ar_msg"
            else
                final_msg="$eng_msg"
            fi
            ;;
        *)
            final_msg="$eng_msg | $ar_msg"  # Default to both
            ;;
    esac
    
    local log_entry="$timestamp [$DEVICE_ID] $log_level $final_msg"
    
    # Console output with colors | إخراج وحدة التحكم بالألوان
    if [[ "${VERBOSE:-true}" == "true" ]] && [[ "$level" != "DEBUG" || "$DEBUG_MODE" == "yes" ]]; then
        echo -e "${log_color}$log_entry\033[0m"
    fi
    
    # Local logging based on LOG_MODE | التسجيل المحلي حسب LOG_MODE
    if [[ "$LOG_MODE" == "local" || "$LOG_MODE" == "both" ]]; then
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null
    fi
    
    # Update message variable for remote logging compatibility
    local message="$log_entry"

    # Remote logging if enabled | التسجيل البعيد إذا كان مفعلاً
    if [[ "$LOG_MODE" == "remote" || "$LOG_MODE" == "both" ]] && [[ "$REMOTE_LOGGING" == "yes" && -n "$log" ]]; then
        if [[ "$level" == "ERROR" || "$level" == "WARN" || "$level" == "SUCCESS" || "$level" == "INFO" ]]; then
            curl -s --connect-timeout 3 --max-time 5 \
                -d "file=awacs.log" \
                -d "data=$message" \
                "$log" >/dev/null 2>&1 &
        fi
    fi
}

# دالة bc_calc محسنة مع معالجة أفضل للأخطاء
bc_calc() {
    local expression="$*"
    local result=""

    [[ -z "$expression" ]] && { echo "0.00"; return 1; }

    if command -v bc &>/dev/null; then
        result=$(echo "scale=2; $expression" | bc -l 2>/dev/null)
        
        if [[ -n "$result" && "$result" != "nan" && "$result" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
            printf "%.2f" "$result" 2>/dev/null || echo "0.00"
            return 0
        fi
    fi
    
    result=$(awk "BEGIN { printf \"%.2f\", ($expression) }" 2>/dev/null)
    
    if [[ -n "$result" && "$result" != "nan" && "$result" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
        echo "$result"
        return 0
    fi
    
    echo "0.00"
    return 1
}

# دالة مقارنة الأرقام العشرية المحسنة
compare_float() {
    local a="$1"
    local op="$2" 
    local b="$3"
    
    [[ -z "$a" || -z "$op" || -z "$b" ]] && return 1
    
    a=$(echo "$a" | tr -d ' ')
    b=$(echo "$b" | tr -d ' ')
    
    if ! [[ "$a" =~ ^-?[0-9]*\.?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
        return 1
    fi
    
    case $op in
        ">")  awk -v a="$a" -v b="$b" 'BEGIN { exit !(a > b) }' ;;
        "<")  awk -v a="$a" -v b="$b" 'BEGIN { exit !(a < b) }' ;;
        ">=") awk -v a="$a" -v b="$b" 'BEGIN { exit !(a >= b) }' ;;
        "<=") awk -v a="$a" -v b="$b" 'BEGIN { exit !(a <= b) }' ;;
        "==") awk -v a="$a" -v b="$b" 'BEGIN { exit !(a == b) }' ;;
        "!=") awk -v a="$a" -v b="$b" 'BEGIN { exit !(a != b) }' ;;
        *)    return 1 ;;
    esac
}

# --------------------------
# دوال مساعدة محسنة للأداء
# --------------------------

# ========================================
# WIFI INTERFACE DETECTION - إدارة واجهات الواي فاي
# ========================================
# يجب أن تكون هذه الدالة قبل get_current_ssid لأنها تحدد WIFI_INTERFACE

detect_wifi_interfaces() {
    local interfaces_found=()
    
    while IFS= read -r interface; do
        [[ -n "$interface" ]] && interfaces_found+=("$interface")
    done < <(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}')
    
    if [[ ${#interfaces_found[@]} -eq 0 ]]; then
        while IFS= read -r interface; do
            [[ -n "$interface" ]] && interfaces_found+=("$interface")
        done < <(iwconfig 2>/dev/null | grep "IEEE 802.11" | awk '{print $1}')
    fi

    if [[ ${#interfaces_found[@]} -eq 0 ]]; then
        log_message "ERROR" "No WiFi interfaces detected" "لم يتم اكتشاف أي واجهات لاسلكية"
        return 1
    fi

    if [[ "$MULTI_INTERFACE" == "yes" && ${#interfaces_found[@]} -gt 1 ]]; then
        log_message "INFO" "Multi-interface mode enabled. Available: ${interfaces_found[*]}" \
                  "تم تفعيل الوضع المتعدد. المتاح: ${interfaces_found[*]}"
        
        local best_interface=""
        local best_score=0
        
        for iface in "${interfaces_found[@]}"; do
            local score=0
            
            if ip link show "$iface" 2>/dev/null | grep -q "UP"; then
                ((score += 2))
                
                local connected_ssid=$(iwgetid "$iface" -r 2>/dev/null || echo "")
                if [[ -n "$connected_ssid" ]]; then
                    ((score += 3))
                    
                    local signal=$(iwconfig "$iface" 2>/dev/null | grep -o '\-[0-9]\+ dBm' | head -1 | tr -d ' dBm-')
                    if [[ -n "$signal" && "$signal" -lt 70 ]]; then
                        ((score += 1))
                    fi
                fi
            fi
            
            if [[ $score -gt $best_score ]]; then
                best_interface="$iface"
                best_score=$score
            fi
        done
        
        WIFI_INTERFACE="${best_interface:-${interfaces_found[0]}}"
        log_message "INFO" "Selected interface: $WIFI_INTERFACE (score: $best_score)" \
                  "تم اختيار الواجهة: $WIFI_INTERFACE (النقاط: $best_score)"
    else
        WIFI_INTERFACE="${interfaces_found[0]}"
        log_message "INFO" "Using single interface: $WIFI_INTERFACE" \
                  "استخدام واجهة واحدة: $WIFI_INTERFACE"
    fi

    if ! iw dev "$WIFI_INTERFACE" info &>/dev/null; then
        log_message "ERROR" "Selected interface $WIFI_INTERFACE is invalid" \
                   "الواجهة المختارة $WIFI_INTERFACE غير صالحة"
        return 1
    fi

    WPACONF="/etc/wpa_supplicant/wpa_supplicant.conf"
    return 0
}

# دالة للحصول على SSID الحالي مع cache لتحسين الأداء - إصلاح تبعية WIFI_INTERFACE
get_current_ssid() {
    local current_time=$(date +%s)
    
    if [[ -n "$CURRENT_SSID_CACHE" && $((current_time - CURRENT_SSID_CACHE_TIME)) -lt $CACHE_VALIDITY_SECONDS ]]; then
        echo "$CURRENT_SSID_CACHE"
        return 0
    fi
    
    # التأكد من وجود WIFI_INTERFACE - إصلاح ترتيب التبعيات
    if [[ -z "$WIFI_INTERFACE" ]]; then
        # اكتشاف تلقائي محسّن وآمن
        local auto_iface=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}')
        if [[ -z "$auto_iface" ]]; then
            auto_iface=$(iwconfig 2>/dev/null | grep "IEEE 802.11" | awk '{print $1; exit}')
        fi
        
        if [[ -n "$auto_iface" ]]; then
            local ssid=$(iwgetid "$auto_iface" -r 2>/dev/null || echo "")
        else
            local ssid=""
        fi
    else
        local ssid=$(iwgetid "$WIFI_INTERFACE" -r 2>/dev/null || echo "")
    fi
    
    CURRENT_SSID_CACHE="$ssid"
    CURRENT_SSID_CACHE_TIME=$current_time
    
    echo "$ssid"
}

# دالة لتهريب SSID بشكل آمن - إصلاح معالجة الأحرف الخاصة المحسّن
safe_escape_ssid() {
    local ssid="$1"
    [[ -z "$ssid" ]] && return 1
    
    # تنظيف المسافات الزائدة أولاً
    ssid=$(echo "$ssid" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/[[:space:]]\+/ /g')
    
    # إزالة الأحرف الخطيرة فقط (control characters) مع المحافظة على الأحرف المفيدة
    ssid=$(echo "$ssid" | tr -d '\000-\037\177')
    
    # تهريب الأحرف الخاصة بطريقة آمنة تماماً
    ssid=$(printf '%s\n' "$ssid" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g')
    
    # التحقق من الصحة النهائية
    if [[ ${#ssid} -gt 32 || ${#ssid} -eq 0 ]]; then
        return 1
    fi
    
    echo "$ssid"
    return 0
}

# --------------------------
# دوال النظام والتبعيات
# --------------------------

# التحقق من وجود الأدوات المطلوبة
check_dependencies() {
    local no_restart=${1:-""}
    local missing_deps=()
    local required_commands=(ip iw iwconfig wpa_cli ping curl bc openssl host)

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_message "WARN" "Missing dependencies: ${missing_deps[*]}" "تبعيات مفقودة: ${missing_deps[*]}"

        if command -v apt-get &>/dev/null; then
            log_message "INFO" "Installing missing dependencies" "تثبيت التبعيات المفقودة"
            
            if sudo apt-get update -y >/dev/null 2>&1; then
                local install_success=true
                
                for pkg in "${missing_deps[@]}"; do
                    case "$pkg" in
                        "host") 
                            if ! sudo apt-get install -y dnsutils >/dev/null 2>&1; then
                                install_success=false
                            fi
                            ;;
                        *) 
                            if ! sudo apt-get install -y "$pkg" >/dev/null 2>&1; then
                                install_success=false
                            fi
                            ;;
                    esac
                done
                
                if $install_success; then
                    log_message "SUCCESS" "Dependencies installed successfully" "تم تثبيت التبعيات بنجاح"
                    [[ "$no_restart" != "no_restart" ]] && exec "$0" "$@"
                else
                    log_message "ERROR" "Some dependencies failed to install" "فشل تثبيت بعض التبعيات"
                fi
            else
                log_message "ERROR" "Failed to update package list" "فشل تحديث قائمة الحزم"
            fi
        else
            log_message "ERROR" "Package manager not found. Please install missing dependencies manually" \
                       "مدير الحزم غير موجود. يرجى تثبيت التبعيات المفقودة يدوياً"
        fi
    fi

    return 0
}

# الدالة المكررة تم حذفها - الدالة الصحيحة في السطر 464

# ========================================
# LOG MANAGEMENT FUNCTIONS - إدارة السجلات
# ========================================

# تحميل السجلات المعلقة
upload_pending_logs() {
    [[ ! -f "$REMOTE_LOG_FILE" || ! -s "$REMOTE_LOG_FILE" ]] && return 0
    
    log_message "INFO" "Uploading pending logs" "تحميل السجلات المعلقة"
    
    local uploaded=0
    local failed=0
    
    while IFS= read -r line && [[ $failed -lt 3 ]]; do
        if timeout 5 curl -s --connect-timeout 3 --max-time 5 \
            --data-urlencode "file=aasw.log" \
            --data-urlencode "data=$line" \
            "$log" &>/dev/null; then
            ((uploaded++))
        else
            ((failed++))
        fi
    done < "$REMOTE_LOG_FILE"
    
    if [[ $failed -lt 3 ]]; then
        > "$REMOTE_LOG_FILE"
        log_message "SUCCESS" "Uploaded $uploaded pending log entries" "تم رفع $uploaded سجل معلق"
    fi
}

# --------------------------
# دوال اختبار الشبكة - مع إصلاح DNS المتقدم
# --------------------------

# **إصلاح DNS المتقدم** - يحل مشكلة DNS hijacking وCaptive portals
fix_dns_issues() {
    local fixed=false
    local backup_file="/etc/resolv.conf.awacs_backup"
    
    log_message "INFO" "Checking DNS configuration" "فحص إعدادات DNS"
    
    # التحقق من صحة ملف resolv.conf
    if [[ ! -r /etc/resolv.conf ]]; then
        log_message "ERROR" "Cannot read /etc/resolv.conf" "لا يمكن قراءة ملف resolv.conf"
        return 1
    fi
    
    # تجربة DNS servers مختلفة - Adaptive Mode
    local dns_ping_timeout dns_test_timeout
    case "$SPEED_MODE" in
        "fast") 
            dns_ping_timeout=1
            dns_test_timeout=2
            ;;
        "balanced") 
            dns_ping_timeout=2
            dns_test_timeout=3
            ;;
        "conservative") 
            dns_ping_timeout=3
            dns_test_timeout=5
            ;;
        *) 
            dns_ping_timeout=2
            dns_test_timeout=3
            ;;
    esac
    
    # إنشاء نسخة احتياطية آمنة
    if [[ ! -f "$backup_file" ]]; then
        if ! sudo cp /etc/resolv.conf "$backup_file" 2>/dev/null; then
            log_message "ERROR" "Failed to create DNS backup" "فشل في إنشاء نسخة احتياطية DNS"
            return 1
        fi
        sudo chmod 644 "$backup_file" 2>/dev/null
    fi
    
    # دالة للتحقق من صحة DNS server
    validate_dns_server() {
        local dns_ip="$1"
        
        # التحقق من صيغة IP
        if ! [[ "$dns_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            return 1
        fi
        
        # التحقق من أن كل جزء من IP صالح (0-255)
        local IFS='.'
        local ip_parts=($dns_ip)
        for part in "${ip_parts[@]}"; do
            if ((part < 0 || part > 255)); then
                return 1
            fi
        done
        
        # اختبار الاتصال
        if ! timeout "$dns_ping_timeout" ping -c 1 -W "$dns_ping_timeout" "$dns_ip" &>/dev/null; then
            return 1
        fi
        
        # اختبار DNS query
        if ! timeout "$dns_test_timeout" nslookup google.com "$dns_ip" &>/dev/null; then
            return 1
        fi
        
        return 0
    }
    
    # تطبيق DNS server بطريقة آمنة
    apply_dns_server() {
        local dns_server="$1"
        local temp_resolv="/tmp/resolv.conf.awacs.$$"
        
        # إنشاء ملف resolv.conf جديد
        {
            echo "# Generated by AWACS - $(date)"
            echo "nameserver $dns_server"
            # إضافة DNS servers الأصلية (إذا كانت مختلفة)
            if [[ -f "$backup_file" ]]; then
                grep "^nameserver" "$backup_file" | grep -v "$dns_server" | head -2
            fi
            echo "# Fallback options"
            echo "options timeout:2 attempts:3"
        } > "$temp_resolv"
        
        # التحقق من صحة الملف المؤقت
        if [[ -s "$temp_resolv" ]] && grep -q "nameserver $dns_server" "$temp_resolv"; then
            if sudo cp "$temp_resolv" /etc/resolv.conf 2>/dev/null; then
                rm -f "$temp_resolv"
                return 0
            fi
        fi
        
        rm -f "$temp_resolv"
        return 1
    }
    
    # اختبار DNS servers الأساسية
    for dns_server in "${PRIMARY_DNS_SERVERS[@]}"; do
        if validate_dns_server "$dns_server"; then
            log_message "INFO" "Applying primary DNS server: $dns_server" "تطبيق خادم DNS أساسي: $dns_server"
            if apply_dns_server "$dns_server"; then
                fixed=true
                break
            fi
        else
            log_message "WARN" "Primary DNS server failed validation: $dns_server" "فشل التحقق من خادم DNS: $dns_server"
        fi
    done
    
    # إذا فشلت الأساسية، تجربة البديلة
    if ! $fixed; then
        log_message "WARN" "Primary DNS servers failed, trying fallback" "فشل خوادم DNS الأساسية، تجربة البديلة"
        for dns_server in "${FALLBACK_DNS_SERVERS[@]}"; do
            if validate_dns_server "$dns_server"; then
                log_message "INFO" "Applying fallback DNS server: $dns_server" "تطبيق خادم DNS بديل: $dns_server"
                if apply_dns_server "$dns_server"; then
                    fixed=true
                    break
                fi
            else
                log_message "WARN" "Fallback DNS server failed validation: $dns_server" "فشل التحقق من خادم DNS البديل: $dns_server"
            fi
        done
    fi
    
    if $fixed; then
        # إعادة تشغيل خدمات DNS إذا كانت موجودة
        if command -v systemctl &>/dev/null; then
            if systemctl is-active systemd-resolved &>/dev/null; then
                sudo systemctl restart systemd-resolved 2>/dev/null || true
                sleep 1
            fi
            if systemctl is-active dnsmasq &>/dev/null; then
                sudo systemctl restart dnsmasq 2>/dev/null || true
                sleep 1
            fi
        fi
        
        # التحقق النهائي من عمل DNS
        if timeout 5 nslookup google.com &>/dev/null; then
            log_message "SUCCESS" "DNS configuration fixed and verified" "تم إصلاح والتحقق من إعدادات DNS"
            return 0
        else
            log_message "WARN" "DNS applied but verification failed" "تم تطبيق DNS لكن فشل التحقق"
            # استرداد النسخة الاحتياطية
            sudo cp "$backup_file" /etc/resolv.conf 2>/dev/null || true
        fi
    fi
    
    log_message "ERROR" "Failed to fix DNS issues" "فشل في إصلاح مشاكل DNS"
    return 1
}

# فحص الاتصال بالإنترنت - محسن مع اختبار متقدم ومقاوم للـ DNS hijacking
check_internet() {
    local test_methods=("ping" "curl" "wget" "nslookup")
    local success_count=0
    local total_tests=0
    
    # تحديد الإعدادات حسب وضع السرعة
    local ping_timeout curl_timeout dns_timeout ping_ips test_urls
    case "$SPEED_MODE" in
        "fast")
            ping_timeout=2
            curl_timeout=3
            dns_timeout=2
            ping_ips=("8.8.8.8" "1.1.1.1")
            test_urls=("http://detectportal.firefox.com/success.txt" "http://www.google.com/generate_204")
            ;;
        "balanced")
            ping_timeout=3
            curl_timeout=5
            dns_timeout=3
            ping_ips=("8.8.8.8" "1.1.1.1" "208.67.222.222")
            test_urls=("http://detectportal.firefox.com/success.txt" "http://www.google.com/generate_204" "http://clients3.google.com/generate_204")
            ;;
        "conservative")
            ping_timeout=5
            curl_timeout=10
            dns_timeout=5
            ping_ips=("8.8.8.8" "1.1.1.1" "208.67.222.222")
            test_urls=("http://detectportal.firefox.com/success.txt" "http://www.google.com/generate_204" "http://clients3.google.com/generate_204" "http://connectivitycheck.gstatic.com/generate_204" "http://captive.apple.com/hotspot-detect.html")
            ;;
        *)
            ping_timeout=3
            curl_timeout=5
            dns_timeout=3
            ping_ips=("8.8.8.8" "1.1.1.1" "208.67.222.222")
            test_urls=("http://detectportal.firefox.com/success.txt" "http://www.google.com/generate_204" "http://clients3.google.com/generate_204")
            ;;
    esac
    
    # اختبار Ping - Adaptive Mode
    for ip in "${ping_ips[@]}"; do
        if timeout $ping_timeout ping -c 1 -W 1 "$ip" &>/dev/null; then
            ((success_count++))
        fi
        ((total_tests++))
    done
    
    # اختبار HTTP requests - Adaptive Mode
    for url in "${test_urls[@]}"; do
        if timeout $curl_timeout curl -sf --max-time $((curl_timeout-1)) "$url" &>/dev/null; then
            ((success_count++))
        elif [[ "$SPEED_MODE" == "conservative" ]] && timeout $curl_timeout wget -q --spider --timeout=$((curl_timeout-1)) "$url" &>/dev/null; then
            ((success_count++))
        fi
        ((total_tests++))
    done
    
    # اختبار DNS resolution - Adaptive Mode
    if timeout $dns_timeout nslookup google.com &>/dev/null; then
        ((success_count++))
    fi
    ((total_tests++))
    
    # نحتاج نجاح 60% على الأقل من الاختبارات
    local success_rate=$((success_count * 100 / total_tests))
    
    if [[ $success_rate -ge 60 ]]; then
        INTERNET_CONNECTED=true
        return 0
    else
        INTERNET_CONNECTED=false
        
        # محاولة إصلاح DNS إذا كان هناك اتصال جزئي
        if [[ $success_count -gt 0 ]]; then
            log_message "WARN" "Partial connectivity detected, attempting DNS fix" \
                       "تم اكتشاف اتصال جزئي، محاولة إصلاح DNS"
            fix_dns_issues
            
            # إعادة الاختبار
            sleep 3
            if timeout 10 curl -sf --max-time 8 "http://detectportal.firefox.com/success.txt" &>/dev/null; then
                INTERNET_CONNECTED=true
                return 0
            fi
        fi
        
        return 1
    fi
}

# قياس السرعة باستخدام wget - مطلوب كـ backup method
measure_speed_wget() {
    for server in "${SPEEDTEST_SERVERS[@]}"; do
        local start_time end_time time_diff
        start_time=$(date +%s.%N)
        
        if timeout 10 wget -q -O /dev/null "$server" 2>/dev/null; then
            end_time=$(date +%s.%N)
            time_diff=$(bc_calc "$end_time - $start_time")
            
            if compare_float "$time_diff" ">" "0"; then
                local file_size=500000
                [[ "$server" == *"test100k"* ]] && file_size=100000
                
                local speed=$(bc_calc "scale=2; $file_size / $time_diff / 125000")
                echo "$speed"
                return 0
            fi
        fi
    done
    echo "0.00"
}

# قياس السرعة محسن
measure_speed() {
    log_message "DEBUG" "Measuring connection speed" "قياس سرعة الاتصال"

    [[ "$TEST_MODE" == "yes" ]] && { echo "5.00"; return 0; }

    local best_speed="0.00"
    local measurement_count=0
    
    # تحديد عدد القياسات حسب وضع السرعة
    local max_measurements connect_timeout max_time
    case "$SPEED_MODE" in
        "fast") 
            max_measurements=1
            connect_timeout=3
            max_time=5
            ;;
        "balanced") 
            max_measurements=2
            connect_timeout=4
            max_time=8
            ;;
        "conservative") 
            max_measurements=3
            connect_timeout=6
            max_time=12
            ;;
        *) 
            max_measurements=2
            connect_timeout=4
            max_time=8
            ;;
    esac
    
    case "$SPEED_TEST_METHOD" in
        "curl"|"auto"|*)
            for server in "${SPEEDTEST_SERVERS[@]}"; do
                [[ $measurement_count -ge $max_measurements ]] && break
                
                local speed_bytes
                speed_bytes=$(curl -s -w "%{speed_download}" -o /dev/null \
                    --connect-timeout $connect_timeout --max-time $max_time "$server" 2>/dev/null)
                
                if [[ -n "$speed_bytes" && "$speed_bytes" != "0" && "$speed_bytes" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    local speed_mbps
                    speed_mbps=$(bc_calc "scale=2; $speed_bytes / 125000")
                    
                    if compare_float "$speed_mbps" ">" "$best_speed"; then
                        best_speed="$speed_mbps"
                    fi
                    
                    ((measurement_count++))
                    compare_float "$speed_mbps" ">" "3.0" && break
                fi
            done
            ;;
        "wget")
            best_speed=$(measure_speed_wget)
            ;;
    esac

    # إذا فشل curl، استخدم wget كـ backup
    if compare_float "$best_speed" "==" "0.00"; then
        best_speed=$(measure_speed_wget)
    fi

    if compare_float "$best_speed" ">" "0"; then
        local current_ssid
        current_ssid=$(get_current_ssid)
        if [[ -n "$current_ssid" ]]; then
            LAST_SUCCESSFUL_SSID="$current_ssid"
            save_last_successful_ssid "$current_ssid"
        fi
        echo "$best_speed"
    else
        echo "0.10"
    fi
}

# --------------------------
# دوال التعافي وإدارة الأخطاء - مطلوبة جداً
# --------------------------

# التعافي من سقوط الاتصال
recover_from_failure() {
    log_message "ERROR" "Recovering from connection failure" "التعافي من فشل الاتصال"

    sudo wpa_cli -i "$WIFI_INTERFACE" disable_network all >/dev/null 2>&1
    sudo ip link set "$WIFI_INTERFACE" down
    sleep 3
    sudo rfkill unblock wifi 2>/dev/null || true
    sleep 2
    sudo ip link set "$WIFI_INTERFACE" up
    sleep 5

    if systemctl is-active --quiet wpa_supplicant; then
        sudo systemctl restart wpa_supplicant >/dev/null 2>&1
        sleep 3
    fi
    
    sudo ifconfig "$WIFI_INTERFACE" up 2>/dev/null || true
    sudo wpa_cli -i "$WIFI_INTERFACE" reassociate >/dev/null 2>&1
    sleep 2
}

# الإعادة النووية للشبكة - مطلوبة جداً
nuclear_reset() {
    log_message "ERROR" "Initiating nuclear reset" "بدء الإعادة النووية للشبكة"
    local reset_success=false

    # المستوى 1: إعادة تشغيل أساسية - Adaptive Mode
    log_message "INFO" "Level 1 reset: Basic interface restart" "المستوى 1: إعادة تشغيل الواجهة"
    sudo ip link set "$WIFI_INTERFACE" down
    case "$SPEED_MODE" in
        "fast") sleep 1 ;;
        "balanced") sleep 2 ;;
        "conservative") sleep 3 ;;
        *) sleep 2 ;;
    esac
    sudo ip link set "$WIFI_INTERFACE" up
    case "$SPEED_MODE" in
        "fast") sleep 1 ;;
        "balanced") sleep 2 ;;
        "conservative") sleep 3 ;;
        *) sleep 2 ;;
    esac
    
    if iwconfig "$WIFI_INTERFACE" 2>/dev/null | grep -q "IEEE 802.11"; then
        log_message "INFO" "Level 1 reset successful" "نجحت إعادة التعيين من المستوى 1"
        reset_success=true
    else
        # المستوى 2: إعادة تشغيل الخدمات
        log_message "INFO" "Level 2 reset: Restarting network services" "المستوى 2: إعادة تشغيل خدمات الشبكة"
        
        sudo wpa_cli -i "$WIFI_INTERFACE" disable_network all >/dev/null 2>&1
        
        if systemctl is-active --quiet wpa_supplicant; then
            sudo systemctl restart wpa_supplicant >/dev/null 2>&1
            case "$SPEED_MODE" in
                "fast") sleep 1 ;;
                "balanced") sleep 2 ;;
                "conservative") sleep 3 ;;
                *) sleep 2 ;;
            esac
        fi
        
        sudo ifconfig "$WIFI_INTERFACE" up 2>/dev/null || true
        case "$SPEED_MODE" in
            "fast") sleep 1 ;;
            "balanced") sleep 2 ;;
            "conservative") sleep 3 ;;
            *) sleep 2 ;;
        esac
        
        if iwconfig "$WIFI_INTERFACE" 2>/dev/null | grep -q "IEEE 802.11"; then
            log_message "INFO" "Level 2 reset successful" "نجحت إعادة التعيين من المستوى 2"
            reset_success=true
        else
            # المستوى 3: إعادة تعيين كاملة
            log_message "WARN" "Level 3 reset: Full network stack reset" "المستوى 3: إعادة تعيين كاملة"
            
            for service in wpa_supplicant NetworkManager dhcpcd; do
                if systemctl is-active --quiet "$service" 2>/dev/null; then
                    sudo systemctl stop "$service" 2>/dev/null || true
                    sleep 1
                fi
            done
            
            sudo rm -f /var/run/wpa_supplicant/* 2>/dev/null || true
            
            sudo ip link set "$WIFI_INTERFACE" down
            case "$SPEED_MODE" in
                "fast") sleep 1 ;;
                "balanced") sleep 2 ;;
                "conservative") sleep 3 ;;
                *) sleep 2 ;;
            esac
            sudo rfkill unblock wifi
            case "$SPEED_MODE" in
                "fast") sleep 1 ;;
                "balanced") sleep 1 ;;
                "conservative") sleep 2 ;;
                *) sleep 1 ;;
            esac
            sudo ip link set "$WIFI_INTERFACE" up
            case "$SPEED_MODE" in
                "fast") sleep 1 ;;
                "balanced") sleep 2 ;;
                "conservative") sleep 3 ;;
                *) sleep 2 ;;
            esac
            
            sudo ip addr flush dev "$WIFI_INTERFACE"
            case "$SPEED_MODE" in
                "fast") sleep 1 ;;
                "balanced") sleep 1 ;;
                "conservative") sleep 2 ;;
                *) sleep 1 ;;
            esac
            
            # إعادة تشغيل الخدمات - بالتوازي في Fast Mode
            if [[ "$SPEED_MODE" == "fast" ]]; then
                sudo systemctl restart wpa_supplicant 2>/dev/null &
                sudo systemctl restart dhcpcd 2>/dev/null &
                wait
                sleep 2
            else
                for service in dhcpcd NetworkManager wpa_supplicant; do
                    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                        sudo systemctl restart "$service" 2>/dev/null || true
                        case "$SPEED_MODE" in
                            "balanced") sleep 1 ;;
                            "conservative") sleep 2 ;;
                            *) sleep 1 ;;
                        esac
                    fi
                done
                
                case "$SPEED_MODE" in
                    "balanced") sleep 3 ;;
                    "conservative") sleep 5 ;;
                    *) sleep 3 ;;
                esac
            fi
            sudo wpa_cli -i "$WIFI_INTERFACE" enable_network all >/dev/null 2>&1
            sudo wpa_cli -i "$WIFI_INTERFACE" reassociate >/dev/null 2>&1
            
            if iwconfig "$WIFI_INTERFACE" 2>/dev/null | grep -q "IEEE 802.11"; then
                log_message "INFO" "Level 3 reset successful" "نجحت إعادة التعيين من المستوى 3"
                reset_success=true
            fi
        fi
    fi

    local current_ssid
    current_ssid=$(get_current_ssid)
    
    if [[ -n "$current_ssid" ]] && check_internet; then
        LAST_SUCCESSFUL_SSID="$current_ssid"
        save_last_successful_ssid "$current_ssid"
        log_message "SUCCESS" "Connected to $current_ssid after reset" "تم الاتصال بـ $current_ssid بعد إعادة التعيين"
        # Adaptive sleep حسب وضع السرعة
        local success_sleep
        case "$SPEED_MODE" in
            "fast") success_sleep=2 ;;
            "balanced") success_sleep=3 ;;
            "conservative") success_sleep=5 ;;
            *) success_sleep=3 ;;
        esac
        sleep $success_sleep
        return 0
    fi
    
    # الملاذ الأخير: إعادة تشغيل النظام
    log_message "ERROR" "Nuclear reset failed, rebooting system as last resort" \
               "فشلت الإعادة النووية، إعادة تشغيل النظام كملاذ أخير"
    sync
    sudo reboot
    return 1
}

# فحص حالة أجهزة الواي فاي
check_wifi_hardware() {
    [[ "$HARDWARE_CHECK" != "yes" ]] && return 0

    local retry_count=0
    local max_retries=3
    local hardware_recovery_failed=false
    
    log_message "DEBUG" "Starting WiFi hardware check" "بدء فحص أجهزة الواي فاي"
    
    while ((retry_count < max_retries)); do
        local hardware_ok=true
        
        # فحص حالة rfkill
        if rfkill list wifi | grep -q "blocked: yes"; then
            log_message "WARN" "WiFi blocked by rfkill, attempting unblock (attempt $((retry_count + 1)))" "الواي فاي محظور، محاولة إلغاء الحظر"
            if ! sudo rfkill unblock wifi 2>/dev/null; then
                log_message "ERROR" "Failed to unblock WiFi with rfkill" "فشل في إلغاء حظر الواي فاي"
                hardware_ok=false
            else
                sleep 2
            fi
        fi
        
        # فحص حالة واجهة الشبكة
        if ! ip link show "$WIFI_INTERFACE" 2>/dev/null | grep -q "UP"; then
            log_message "WARN" "WiFi interface down, bringing up (attempt $((retry_count + 1)))" "واجهة الواي فاي معطلة، تفعيل"
            if ! sudo ip link set "$WIFI_INTERFACE" up 2>/dev/null; then
                log_message "ERROR" "Failed to bring up WiFi interface" "فشل في تفعيل واجهة الواي فاي"
                hardware_ok=false
            else
                sleep 2
            fi
        fi
        
        # فحص IEEE 802.11 capability
        if ! iwconfig "$WIFI_INTERFACE" 2>/dev/null | grep -q "IEEE 802.11"; then
            log_message "WARN" "WiFi interface not showing 802.11 capability (attempt $((retry_count + 1)))" "واجهة الواي فاي لا تظهر قدرة 802.11"
            hardware_ok=false
            
            # محاولة إصلاح عميق للأجهزة
            if ((retry_count < max_retries - 1)); then
                log_message "INFO" "Attempting hardware recovery" "محاولة استرداد الأجهزة"
                
                # إعادة تحميل driver إذا أمكن
                local wifi_driver=$(lspci -k | grep -A 3 "Network controller\|Wireless" | grep "Kernel driver in use" | awk '{print $5}' | head -1)
                if [[ -n "$wifi_driver" ]]; then
                    log_message "INFO" "Reloading WiFi driver: $wifi_driver" "إعادة تحميل تعريف الواي فاي: $wifi_driver"
                    
                    # إيقاف الواجهة أولاً
                    sudo ip link set "$WIFI_INTERFACE" down 2>/dev/null || true
                    sleep 1
                    
                    # إعادة تحميل التعريف
                    if sudo modprobe -r "$wifi_driver" 2>/dev/null; then
                        sleep 2
                        if sudo modprobe "$wifi_driver" 2>/dev/null; then
                            sleep 3
                            log_message "INFO" "WiFi driver reloaded successfully" "تم إعادة تحميل التعريف بنجاح"
                        else
                            log_message "ERROR" "Failed to reload WiFi driver" "فشل في إعادة تحميل التعريف"
                        fi
                    fi
                    
                    # إعادة تفعيل الواجهة
                    sudo ip link set "$WIFI_INTERFACE" up 2>/dev/null || true
                    sleep 2
                fi
                
                # محاولة إعادة تشغيل خدمة networking
                if command -v systemctl &>/dev/null; then
                    if systemctl is-active networking &>/dev/null; then
                        log_message "INFO" "Restarting networking service" "إعادة تشغيل خدمة الشبكة"
                        sudo systemctl restart networking 2>/dev/null || true
                        sleep 3
                    fi
                fi
            fi
        fi
        
        # إذا نجح كل شيء، خروج من الحلقة
        if $hardware_ok; then
            # اختبار نهائي - محاولة scan بسيط
            if timeout 5 iwlist "$WIFI_INTERFACE" scan &>/dev/null || timeout 5 iw dev "$WIFI_INTERFACE" scan &>/dev/null; then
                log_message "SUCCESS" "WiFi hardware check passed" "نجح فحص أجهزة الواي فاي"
                return 0
            else
                log_message "WARN" "WiFi hardware responding but scan failed" "الأجهزة تستجيب لكن فشل الفحص"
                hardware_ok=false
            fi
        fi
        
        ((retry_count++))
        
        if ((retry_count < max_retries)); then
            log_message "INFO" "Hardware check retry $retry_count/$max_retries in 5 seconds" "إعادة محاولة فحص الأجهزة $retry_count/$max_retries"
            sleep 5
        fi
    done
    
    # فشل كل المحاولات
    log_message "ERROR" "WiFi hardware check failed after $max_retries attempts" "فشل فحص أجهزة الواي فاي بعد $max_retries محاولات"
    
    # محاولة أخيرة - استخدام واجهة بديلة إذا كانت متوفرة
    local backup_interfaces=($(iwconfig 2>/dev/null | grep "IEEE 802.11" | awk '{print $1}' | grep -v "$WIFI_INTERFACE"))
    if [[ ${#backup_interfaces[@]} -gt 0 ]]; then
        local backup_interface="${backup_interfaces[0]}"
        log_message "WARN" "Trying backup WiFi interface: $backup_interface" "تجربة واجهة واي فاي بديلة: $backup_interface"
        WIFI_INTERFACE="$backup_interface"
        
        # إعادة اختبار مع الواجهة البديلة
        if iwconfig "$WIFI_INTERFACE" 2>/dev/null | grep -q "IEEE 802.11"; then
            log_message "SUCCESS" "Switched to backup WiFi interface: $backup_interface" "تم التبديل لواجهة واي فاي بديلة: $backup_interface"
            return 0
        fi
    fi
    
    return 1
}

# فحص حالة wpa_supplicant
check_wpa_supplicant_status() {
    log_message "DEBUG" "Checking wpa_supplicant status" "التحقق من حالة wpa_supplicant"
    
    if ! pgrep -x wpa_supplicant >/dev/null; then
        log_message "ERROR" "wpa_supplicant process not running" "عملية wpa_supplicant غير مشغلة"
        
        if systemctl is-enabled --quiet wpa_supplicant 2>/dev/null; then
            log_message "INFO" "Restarting wpa_supplicant service" "إعادة تشغيل خدمة wpa_supplicant"
            sudo systemctl restart wpa_supplicant >/dev/null 2>&1
            sleep 3
        else
            log_message "INFO" "Starting wpa_supplicant manually" "بدء wpa_supplicant يدوياً"
            sudo wpa_supplicant -B -i "$WIFI_INTERFACE" -c "$WPACONF" >/dev/null 2>&1
            sleep 3
        fi
        
        if pgrep -x wpa_supplicant >/dev/null; then
            log_message "SUCCESS" "wpa_supplicant restarted successfully" "تمت إعادة تشغيل wpa_supplicant بنجاح"
            return 0
        else
            log_message "ERROR" "Failed to restart wpa_supplicant" "فشل إعادة تشغيل wpa_supplicant"
            return 1
        fi
    fi
    
    if ! sudo wpa_cli -i "$WIFI_INTERFACE" ping >/dev/null 2>&1; then
        log_message "ERROR" "Cannot communicate with wpa_supplicant" "لا يمكن الاتصال بـ wpa_supplicant"
        return 1
    fi
    
    return 0
}

# --------------------------
# دوال تحليل وتقييم الشبكات - مطلوبة لاختيار أفضل شبكة
# --------------------------

# حساب نقاط الشبكة - مطلوب
calculate_network_score() {
    local speed=$1
    local signal=$2
    local priority=${3:-5}
    local current=${4:-0}

    if ! [[ "$signal" =~ ^-?[0-9]+$ ]]; then
        echo "0"
        return 1
    fi

    local signal_strength=$((${signal#-}))

    if ((signal_strength > 85)); then
        echo "0"
        return 2
    fi

    local signal_score=$(((100 - signal_strength) > 0 ? (100 - signal_strength) : 0))

    local speed_score=0
    if compare_float "$speed" ">" "10"; then
        speed_score=100
    else
        speed_score=$(bc_calc "$speed * 10")
    fi

    local current_bonus=0
    [[ "$current" == "1" ]] && current_bonus=25

    local total_score
    total_score=$(bc_calc "scale=2; ($speed_score * ${SCORE_WEIGHTS["speed"]}/100) + ($signal_score * ${SCORE_WEIGHTS["signal"]}/100) + ($priority * ${SCORE_WEIGHTS["priority"]}/100) + $current_bonus")

    echo "$total_score"
}

# تحليل الشبكات المتاحة - مطلوب
analyze_available_networks() {
    local scan_results="$1"
    local current_ssid
    current_ssid=$(get_current_ssid)
    local current_has_internet
    current_has_internet=$(check_internet && echo "1" || echo "0")
    local networks_info=""

    [[ -z "$scan_results" ]] && return

    while IFS=$'\t' read -r bssid ssid signal; do
        [[ -z "$bssid" || -z "$ssid" ]] && continue
        
        if ! is_valid_ssid "$ssid"; then
            continue
        fi

        local signal_val
        signal_val=$(echo "$signal" | grep -oE '[-+]?[0-9]+' | head -1)
        [[ ! "$signal_val" =~ ^-?[0-9]+$ ]] && continue

        local priority=0
        local is_current=0

        if [[ "$ssid" == "$current_ssid" ]]; then
            if [[ "$current_has_internet" == "1" ]]; then
                priority=120
            else
                priority=90
            fi
            is_current=1
        elif [[ -n "${SAFETY_NET[$ssid]}" ]]; then
            priority=100
        elif sudo wpa_cli -i "$WIFI_INTERFACE" list_networks 2>/dev/null | sed 's/"//g' | awk '{print $2}' | grep -qFx "$ssid"; then
            priority=80
        elif [[ -f "$TEMP_WIFI_FILE" ]] && grep -Fq "$ssid" "$TEMP_WIFI_FILE"; then
            priority=40
        else
            priority=10
        fi

        local est_speed
        est_speed=$(bc_calc "scale=2; (120 + $signal_val) * 0.2")

        if compare_float "$est_speed" "<" "0.1"; then
            est_speed="0.10"
        elif compare_float "$est_speed" ">" "25"; then
            est_speed="25.00"
        fi

        local score
        score=$(calculate_network_score "$est_speed" "$signal_val" "$priority" "$is_current")

        networks_info="${networks_info}${ssid}|${signal_val}|${est_speed}|${score}|${is_current}|${priority}\n"
    done <<< "$scan_results"

    echo -e "$networks_info" | sort -t "|" -k4,4rn
}

# البحث عن أفضل شبكة - مطلوب
find_best_network() {
    local current_ssid
    current_ssid=$(get_current_ssid)
    local current_has_internet
    current_has_internet=$(check_internet && echo "1" || echo "0")
    local scan_results
    scan_results=$(scan_networks)
    local networks_info
    networks_info=$(analyze_available_networks "$scan_results")

    [[ -z "$networks_info" ]] && return

    local best_network=""
    local best_score=0
    local current_network=""
    local current_score=0

    while IFS="|" read -r ssid signal speed score is_current priority; do
        [[ -z "$ssid" ]] && continue

        if [[ "$is_current" == "1" ]]; then
            current_network="$ssid"
            current_score="$score"
        fi

        if [[ -z "$best_network" ]] || compare_float "$score" ">" "$best_score"; then
            best_network="$ssid"
            best_score="$score"
        fi
    done <<< "$networks_info"

    if [[ "$current_network" == "$best_network" ]]; then
        return
    fi

    if [[ -n "$current_network" ]]; then
        local improvement_ratio
        improvement_ratio=$(bc_calc "scale=2; $best_score / ($current_score + 0.01)")

        if [[ "$current_has_internet" == "1" ]]; then
            if ! compare_float "$improvement_ratio" ">" "$SPEED_THRESHOLD"; then
                return
            fi

            if compare_float "$current_score" ">" "80" && ! compare_float "$improvement_ratio" ">" "$NEVER_BREAK_THRESHOLD"; then
                return
            fi
        else
            if ! compare_float "$improvement_ratio" ">" "1.1"; then
                return
            fi
        fi
    fi

    echo "$best_network"
}

# --------------------------
# الخوارزمية التكيفية - مطلوبة
# --------------------------

# ضبط فترة المسح ديناميكياً
adjust_scan_interval() {
    local connection_stable=$1
    
    if [[ "$connection_stable" == "1" ]]; then
        ((CONSECUTIVE_STABLE_CONNECTIONS++))
        
        if ((CONSECUTIVE_STABLE_CONNECTIONS > 5)); then
            ADAPTIVE_SCAN_INTERVAL=$((ADAPTIVE_SCAN_INTERVAL + 15))
            if ((ADAPTIVE_SCAN_INTERVAL > MAX_SCAN_INTERVAL)); then
                ADAPTIVE_SCAN_INTERVAL=$MAX_SCAN_INTERVAL
            fi
        fi
    else
        CONSECUTIVE_STABLE_CONNECTIONS=0
        ADAPTIVE_SCAN_INTERVAL=$MIN_SCAN_INTERVAL
    fi
    
    SCAN_INTERVAL=$ADAPTIVE_SCAN_INTERVAL
}

# --------------------------
# إدارة الشبكات
# --------------------------

# مسح الشبكات
scan_networks() {
    local current_time=$(date +%s)

    [[ "$TEST_MODE" == "yes" && -f "$LAST_SCAN_FILE" ]] && { cat "$LAST_SCAN_FILE"; return 0; }

    if ((current_time - LAST_SCAN_TIME < ADAPTIVE_SCAN_INTERVAL)) && [[ -f "$LAST_SCAN_FILE" && -s "$LAST_SCAN_FILE" ]]; then
        cat "$LAST_SCAN_FILE"
        return 0
    fi

    log_message "DEBUG" "Performing network scan" "جاري مسح الشبكات"

    sleep $PRE_SCAN_SLEEP
    sudo iw dev "$WIFI_INTERFACE" set power_save off >/dev/null 2>&1

    local scan_output=""
    local retry_count=0
    # Adaptive retries حسب وضع السرعة
    local max_retries
    case "$SPEED_MODE" in
        "fast") max_retries=3 ;;
        "balanced") max_retries=4 ;;
        "conservative") max_retries=$([ "$SYSTEM_BOOTING" = "true" ] && echo 8 || echo 5) ;;
        *) max_retries=4 ;;
    esac

    while [[ $retry_count -lt $max_retries ]]; do
        local temp_scan="$SCAN_OUTPUT_TMP.$$"
        
        if timeout 15 sudo iw dev "$WIFI_INTERFACE" scan 2>/dev/null > "$temp_scan"; then
            scan_output=$(cat "$temp_scan" 2>/dev/null)
        fi
        
        if [[ -z "$scan_output" ]]; then
            if timeout 15 sudo iwlist "$WIFI_INTERFACE" scan 2>/dev/null > "$temp_scan"; then
                scan_output=$(cat "$temp_scan" 2>/dev/null)
            fi
        fi
        
        rm -f "$temp_scan" 2>/dev/null

        if [[ -n "$scan_output" && "$scan_output" != *"Device or resource busy"* ]]; then
            break
        fi

        # Adaptive sleep حسب وضع السرعة
        local sleep_time
        case "$SPEED_MODE" in
            "fast") sleep_time=1 ;;
            "balanced") sleep_time=$((retry_count + 1)) ;;
            "conservative") sleep_time=$((retry_count + 2)) ;;
            *) sleep_time=$((retry_count + 1)) ;;
        esac
        sleep $sleep_time
        ((retry_count++))
    done

    if [[ -z "$scan_output" || "$scan_output" == *"Device or resource busy"* ]]; then
        [[ -f "$LAST_SCAN_FILE" && -s "$LAST_SCAN_FILE" ]] && cat "$LAST_SCAN_FILE"
        return 1
    fi

    # تحليل النتائج
    local result=""
    if [[ "$scan_output" == *"BSS "* ]]; then
        result=$(echo "$scan_output" | awk '
            BEGIN { RS="BSS "; FS="\n" }
            NR > 1 {
                mac = $1; ssid = ""; signal = ""
                for (i=1; i<=NF; i++) {
                    if ($i ~ /SSID:/) {
                        split($i, a, "SSID: ")
                        if (length(a[2]) > 0 && a[2] != "\\x00") ssid = a[2]
                    }
                    if ($i ~ /signal:/) {
                        split($i, a, "signal: ")
                        signal = a[2]
                    }
                }
                if (mac && ssid && signal && length(ssid) <= 32 && ssid !~ /^[\[\](){}]/) {
                    gsub(/[\(\)\r\n\t]/, "", mac)
                    gsub(/[\r\n\t]/, "", ssid)
                    print mac "\t" ssid "\t" signal
                }
            }
        ')
    else
        result=$(echo "$scan_output" | awk '
            /Cell [0-9]+ - Address:/ {
                if (mac && ssid && signal && length(ssid) <= 32 && ssid !~ /^[\[\](){}]/) {
                    print mac "\t" ssid "\t" signal
                }
                mac = $5; ssid = ""; signal = ""
            }
            /ESSID:/ {
                sub(/.*ESSID:"/, ""); sub(/".*/, "")
                if (length($0) > 0) ssid = $0
            }
            /Quality=|Signal level=/ {
                if ($0 ~ /Signal level=-[0-9]+/) {
                    match($0, /-[0-9]+/)
                    signal = substr($0, RSTART, RLENGTH)
                } else if ($0 ~ /Signal level=[0-9]+\/[0-9]+/) {
                    signal = "-70"
                }
            }
            END {
                if (mac && ssid && signal && length(ssid) <= 32 && ssid !~ /^[\[\](){}]/) {
                    print mac "\t" ssid "\t" signal
                }
            }
        ')
    fi

    if [[ -n "$result" ]]; then
        echo "$result" > "$LAST_SCAN_FILE"
        LAST_SCAN_TIME=$current_time
        echo "$result"
        return 0
    else
        [[ -f "$LAST_SCAN_FILE" && -s "$LAST_SCAN_FILE" ]] && cat "$LAST_SCAN_FILE"
        return 1
    fi
}

# التحقق من صحة SSID
is_valid_ssid() {
    local ssid="$1"
    
    [[ -z "$ssid" ]] && return 1
    [[ "$ssid" =~ ^\[ ]] && return 1
    [[ ${#ssid} -gt 32 ]] && return 1
    [[ "$ssid" == *"INFO"* || "$ssid" == *"DEBUG"* || "$ssid" == *"ERROR"* ]] && return 1
    [[ "$ssid" =~ ^[[:space:]]*$ ]] && return 1
    
    return 0
}

# الاتصال بشبكة محددة
connect_to_network() {
    local ssid="$1"
    local keep_connection="${2:-0}"
    
    if ! is_valid_ssid "$ssid"; then
        log_message "WARN" "Invalid SSID format: $ssid" "صيغة SSID غير صالحة: $ssid"
        return 1
    fi

    log_message "INFO" "Attempting to connect to $ssid" "محاولة الاتصال بشبكة $ssid"

    local network_id=""
    local networks_list
    networks_list=$(sudo wpa_cli -i "$WIFI_INTERFACE" list_networks 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$networks_list" ]]; then
        while IFS=$'\t' read -r id network_name flags; do
            [[ "$id" == "network id" ]] && continue
            
            local clean_name="${network_name//\"/}"
            if [[ "$clean_name" == "$ssid" ]]; then
                network_id="$id"
                break
            fi
        done <<< "$networks_list"
    fi

    if [[ -z "$network_id" || "$network_id" == "network" ]]; then
        network_id=$(sudo wpa_cli -i "$WIFI_INTERFACE" add_network 2>/dev/null)
        
        if [[ -z "$network_id" || "$network_id" == "FAIL" ]]; then
            log_message "ERROR" "Failed to add network $ssid" "فشل إضافة شبكة $ssid"
            return 1
        fi

        local escaped_ssid
        if ! escaped_ssid=$(safe_escape_ssid "$ssid"); then
            log_message "ERROR" "Failed to escape SSID: $ssid" "فشل تهريب SSID: $ssid"
            sudo wpa_cli -i "$WIFI_INTERFACE" remove_network "$network_id" >/dev/null 2>&1
            return 1
        fi
        
        if ! sudo wpa_cli -i "$WIFI_INTERFACE" set_network "$network_id" ssid "\"$escaped_ssid\"" >/dev/null 2>&1; then
            log_message "ERROR" "Failed to set SSID for network $ssid" "فشل تعيين SSID للشبكة $ssid"
            sudo wpa_cli -i "$WIFI_INTERFACE" remove_network "$network_id" >/dev/null 2>&1
            return 1
        fi
        
        sudo wpa_cli -i "$WIFI_INTERFACE" set_network "$network_id" key_mgmt NONE >/dev/null 2>&1
        sudo wpa_cli -i "$WIFI_INTERFACE" set_network "$network_id" priority 5 >/dev/null 2>&1

        echo "$ssid" >> "$TEMP_WIFI_FILE"
        
        if [[ $(wc -l < "$TEMP_WIFI_FILE" 2>/dev/null || echo 0) -gt $MAX_TEMP_NETWORKS ]]; then
            tail -n $MAX_TEMP_NETWORKS "$TEMP_WIFI_FILE" > "$TEMP_WIFI_FILE.tmp" 2>/dev/null
            mv "$TEMP_WIFI_FILE.tmp" "$TEMP_WIFI_FILE" 2>/dev/null
        fi
    fi

    if [[ "$keep_connection" != "1" ]]; then
        sudo wpa_cli -i "$WIFI_INTERFACE" disable_network all >/dev/null 2>&1
    fi

    if ! sudo wpa_cli -i "$WIFI_INTERFACE" enable_network "$network_id" >/dev/null 2>&1; then
        log_message "ERROR" "Failed to enable network $ssid" "فشل تفعيل شبكة $ssid"
        return 1
    fi
    
    if ! sudo wpa_cli -i "$WIFI_INTERFACE" select_network "$network_id" >/dev/null 2>&1; then
        log_message "ERROR" "Failed to select network $ssid" "فشل اختيار شبكة $ssid"
        return 1
    fi

    sleep $SWITCH_TIMEOUT

    # تحديد عدد المحاولات حسب وضع السرعة
    local max_connect_retries
    case "$SPEED_MODE" in
        "fast") max_connect_retries=2 ;;
        "balanced") max_connect_retries=3 ;;
        "conservative") max_connect_retries=4 ;;
        *) max_connect_retries=3 ;;
    esac
    
    for retry in $(seq 1 $max_connect_retries); do
        local connected_ssid
        connected_ssid=$(get_current_ssid)

        if [[ "$connected_ssid" == "$ssid" ]]; then
            if check_internet; then
                local speed
                speed=$(measure_speed)
                log_message "SUCCESS" "Connected to $ssid (Speed: ${speed}Mbps)" \
                          "تم الاتصال بـ $ssid (السرعة: ${speed}Mbps)"
                return 0
            else
                log_message "WARN" "Connected to $ssid but no internet (attempt $retry/3)" \
                          "تم الاتصال بـ $ssid لكن لا يوجد إنترنت (محاولة $retry/3)"
                [[ $retry -lt 3 ]] && sleep 3
            fi
        else
            log_message "WARN" "Failed to connect to $ssid, got $connected_ssid (attempt $retry/3)" \
                      "فشل الاتصال بـ $ssid، تم الاتصال بـ $connected_ssid (محاولة $retry/3)"
            [[ $retry -lt 3 ]] && sleep 3
        fi
    done

    log_message "ERROR" "Failed to establish connection to $ssid after 3 attempts" \
               "فشل إنشاء اتصال مع $ssid بعد 3 محاولات"
    return 1
}

# البحث عن الشبكات المفتوحة - مطلوب
find_open_networks() {
    local scan_results
    scan_results=$(scan_networks)
    local open_networks=""

    [[ -z "$scan_results" ]] && return

    while IFS=$'\t' read -r bssid ssid signal; do
        [[ -z "$ssid" ]] && continue
        
        if ! is_valid_ssid "$ssid"; then
            continue
        fi

        local signal_val
        signal_val=$(echo "$signal" | grep -oE '[-+]?[0-9]+' | head -1)
        [[ ! "$signal_val" =~ ^-?[0-9]+$ ]] && continue

        local abs_signal=${signal_val#-}
        ((abs_signal > 80)) && continue

        open_networks="${open_networks}${ssid}\n"
    done <<< "$scan_results"

    echo -e "$open_networks" | sort -u
}

# تجربة الاتصال بالشبكات المفتوحة - مطلوب
try_open_networks() {
    local open_networks
    open_networks=$(find_open_networks)

    if [[ -z "$open_networks" ]]; then
        return 1
    fi

    while read -r ssid; do
        if ! is_valid_ssid "$ssid"; then
            continue
        fi

        if connect_to_network "$ssid"; then
            if check_internet; then
                local speed
                speed=$(measure_speed)
                log_message "SUCCESS" "Connected to open network: $ssid with internet (Speed: ${speed}Mbps)" \
                          "تم الاتصال بشبكة مفتوحة: $ssid مع إنترنت (السرعة: ${speed}Mbps)"
                LAST_SUCCESSFUL_SSID="$ssid"
                return 0
            fi
        fi
    done <<< "$open_networks"

    return 1
}

# وظيفة الاتصال العدواني - مطلوبة للحالات التي لا يوجد فيها اتصال بالإنترنت
aggressive_connect() {
    log_message "INFO" "Starting smart aggressive connection mode" "بدء وضع الاتصال الذكي"
    
    local scan_results
    scan_results=$(scan_networks)
    
    local available_networks=()
    while IFS=$'\t' read -r bssid ssid signal; do
        [[ -z "$ssid" ]] && continue
        if is_valid_ssid "$ssid"; then
            available_networks+=("$ssid")
        fi
    done <<< "$scan_results"
    
    if [[ ${#available_networks[@]} -eq 0 ]]; then
        log_message "WARN" "No available networks found in scan" "لم يتم العثور على شبكات متاحة في المسح"
        if [[ "$AUTO_CONNECT_OPEN" == "yes" ]] && try_open_networks; then
            return 0
        fi
        
        log_message "ERROR" "All connection attempts failed, performing nuclear reset" "فشلت جميع محاولات الاتصال"
        nuclear_reset
        
        local current_ssid
        current_ssid=$(get_current_ssid)
        
        if [[ -n "$current_ssid" ]] && check_internet; then
            log_message "SUCCESS" "Connected to $current_ssid after reset" "تم الاتصال بـ $current_ssid بعد إعادة التعيين"
            return 0
        fi
        
        return 1
    fi
    
    # تجربة الشبكات المتاحة
    for ssid in "${available_networks[@]}"; do
        if connect_to_network "$ssid"; then
            if check_internet; then
                local speed
                speed=$(measure_speed)
                log_message "SUCCESS" "Connected to $ssid with speed ${speed}Mbps" "تم الاتصال بـ $ssid بسرعة ${speed}Mbps"
                LAST_SUCCESSFUL_SSID="$ssid"
                save_last_successful_ssid "$ssid"
                return 0
            fi
        fi
    done
    
    # إذا فشلت جميع المحاولات، تجربة الشبكات المفتوحة
    if [[ "$AUTO_CONNECT_OPEN" == "yes" ]] && try_open_networks; then
        return 0
    fi
    
    return 1
}

# اختبار الاتصال الحالي وتحسينه - مطلوب
test_and_optimize_connection() {
    local current_ssid
    current_ssid=$(get_current_ssid)

    if [[ -z "$current_ssid" ]]; then
        log_message "WARN" "Not connected to any network" "غير متصل بأي شبكة"
        return 1
    fi

    if ! check_internet; then
        log_message "WARN" "Connected to $current_ssid but no internet access" \
                   "متصل بـ $current_ssid ولكن لا يوجد اتصال بالإنترنت"
        return 1
    fi

    local current_speed
    current_speed=$(measure_speed)

    log_message "INFO" "Connected to $current_ssid with speed ${current_speed}Mbps" \
              "متصل بشبكة $current_ssid بسرعة ${current_speed} ميجابت/ثانية"

    if compare_float "$current_speed" "<" "$MIN_SPEED"; then
        ((LOW_SPEED_COUNT++))
        log_message "WARN" "Speed below threshold ($LOW_SPEED_COUNT/$LOW_SPEED_THRESHOLD)" \
                   "السرعة أقل من الحد الأدنى ($LOW_SPEED_COUNT/$LOW_SPEED_THRESHOLD)"
    
        if [[ $LOW_SPEED_COUNT -ge $LOW_SPEED_THRESHOLD ]]; then
            LOW_SPEED_COUNT=0
            log_message "WARN" "Multiple low speed detections, searching for better network" \
                       "تكرارات سرعة منخفضة، جاري البحث عن شبكة أفضل"
        
            if aggressive_connect; then
                return 0
            fi
        else
            return 0
        fi
    else
        LOW_SPEED_COUNT=0
    fi

    return 0
}

# --------------------------
# الوضع الليلي
# --------------------------

check_night_mode() {
    [[ "$NIGHT_MODE" != "yes" ]] && return 0
    
    local current_time=$(date +%H:%M)
    local current_minutes=$((10#${current_time%:*} * 60 + 10#${current_time#*:}))
    local night_start_minutes=$((10#${NIGHT_START%:*} * 60 + 10#${NIGHT_START#*:}))
    local night_end_minutes=$((10#${NIGHT_END%:*} * 60 + 10#${NIGHT_END#*:}))

    local is_night_mode=false

    if ((night_end_minutes < night_start_minutes)); then
        if ((current_minutes >= night_start_minutes || current_minutes <= night_end_minutes)); then
            is_night_mode=true
        fi
    else
        if ((current_minutes >= night_start_minutes && current_minutes <= night_end_minutes)); then
            is_night_mode=true
        fi
    fi

    if $is_night_mode; then
        if ((CHECK_INTERVAL != NIGHT_CHECK_INTERVAL)); then
            CHECK_INTERVAL=$NIGHT_CHECK_INTERVAL
            MIN_SPEED=0.3
            SPEED_THRESHOLD=3.0
            NEVER_BREAK_THRESHOLD=1.5
        fi
    else
        if ((CHECK_INTERVAL != ORIGINAL_CHECK_INTERVAL)); then
            CHECK_INTERVAL=$ORIGINAL_CHECK_INTERVAL
            MIN_SPEED=$ORIGINAL_MIN_SPEED
            SPEED_THRESHOLD=1.5
            NEVER_BREAK_THRESHOLD=1.2
        fi
    fi
}

# إدارة الشبكات المخزنة
manage_stored_networks() {
    local current_networks
    current_networks=$(sudo wpa_cli -i "$WIFI_INTERFACE" list_networks | tail -n +3 | wc -l)

    if ((current_networks > MAX_NETWORK_SIZE)); then
        local networks_to_remove=$((current_networks - MAX_NETWORK_SIZE))
        local emergency_nets=()

        for ssid in "${!SAFETY_NET[@]}"; do
            emergency_nets+=("$ssid")
        done

        local stored_networks
        stored_networks=$(sudo wpa_cli -i "$WIFI_INTERFACE" list_networks | awk -F'\t' 'NR>2 {print $1, $2}')

        while read -r network && ((networks_to_remove > 0)); do
            local network_id network_name
            network_id=$(echo "$network" | cut -f1)
            network_name=$(echo "$network" | cut -f2 | tr -d '"')

            local is_emergency=false
            for emergency_ssid in "${emergency_nets[@]}"; do
                if [[ "$network_name" == "$emergency_ssid" ]]; then
                    is_emergency=true
                    break
                fi
            done

            if ! $is_emergency; then
                sudo wpa_cli -i "$WIFI_INTERFACE" remove_network "$network_id" &>/dev/null
                ((networks_to_remove--))
            fi
        done <<< "$stored_networks"

        if [[ "$READ_ONLY_WPA" != "yes" ]]; then
            sudo wpa_cli -i "$WIFI_INTERFACE" save_config &>/dev/null
        fi
    fi
}

# التعامل مع الشبكات المخفية
handle_hidden_networks() {
    if [[ "$CONNECT_HIDDEN" == "yes" ]]; then
        local stored_networks
        stored_networks=$(sudo wpa_cli -i "$WIFI_INTERFACE" list_networks | tail -n +3 | awk '{print $1}')

        for network_id in $stored_networks; do
            sudo wpa_cli -i "$WIFI_INTERFACE" set_network "$network_id" scan_ssid 1 >/dev/null
        done

        if [[ "$READ_ONLY_WPA" != "yes" ]]; then
            sudo wpa_cli -i "$WIFI_INTERFACE" save_config >/dev/null
        fi
    fi
}

# تفعيل وضع التخفي - قد يكون مطلوب لاحقاً
enable_stealth_mode() {
    if [[ "$STEALTH_MODE" == "yes" ]]; then
        log_message "INFO" "Activating stealth mode" "تفعيل وضع التخفي"

        sudo iptables -A OUTPUT -p icmp --icmp-type echo-request -j DROP &>/dev/null || true
        sudo systemctl stop avahi-daemon &>/dev/null || true
        sudo systemctl stop mdns &>/dev/null || true

        if [[ -f /etc/dhcp/dhclient.conf ]]; then
            sudo cp /etc/dhcp/dhclient.conf /etc/dhcp/dhclient.conf.bak 2>/dev/null
            sudo sed -i 's/send host-name/#send host-name/g' /etc/dhcp/dhclient.conf
        fi
    fi
}

# --------------------------
# إدارة الملفات
# --------------------------

setup_temp_files() {
    if ! mkdir -p "$TEMP_WIFI_DIR" 2>/dev/null; then
        log_message "ERROR" "Failed to create temp directory: $TEMP_WIFI_DIR" "فشل إنشاء المجلد المؤقت"
        return 1
    fi
    
    chmod 700 "$TEMP_WIFI_DIR" 2>/dev/null
    
    local temp_files=(
        "$REMOTE_LOG_FILE"
        "$TEMP_WIFI_FILE" 
        "$LAST_SUCCESSFUL_SSID_FILE"
        "$LAST_SCAN_FILE"
    )
    
    for file in "${temp_files[@]}"; do
        if ! touch "$file" 2>/dev/null; then
            log_message "WARN" "Failed to create temp file: $file" "فشل إنشاء ملف مؤقت: $file"
        else
            chmod 600 "$file" 2>/dev/null
        fi
    done
    
    return 0
}

cleanup_temp_files() {
    if [[ -f "$LOG_FILE" ]]; then
        local file_size
        file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        
        if ((file_size > 1048576)); then
            if tail -n 1000 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null; then
                mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null
            fi
        fi
    fi

    if [[ -f "$REMOTE_LOG_FILE" ]]; then
        local line_count
        line_count=$(wc -l < "$REMOTE_LOG_FILE" 2>/dev/null || echo 0)
        
        if ((line_count > 500)); then
            if tail -n 500 "$REMOTE_LOG_FILE" > "$TEMP_WIFI_DIR/remote_logs.tmp" 2>/dev/null; then
                mv "$TEMP_WIFI_DIR/remote_logs.tmp" "$REMOTE_LOG_FILE" 2>/dev/null
            fi
        fi
    fi

    find "$TEMP_WIFI_DIR" -name "scan_*.tmp" -type f -mtime +1 -delete 2>/dev/null || true
    find /tmp -name "wget-*" -o -name "curl-*" -type f -mtime +1 -delete 2>/dev/null || true
}

save_last_successful_ssid() {
    local ssid="$1"
    [[ -z "$ssid" ]] && return 1
    
    if echo "$ssid" > "$LAST_SUCCESSFUL_SSID_FILE" 2>/dev/null; then
        chmod 600 "$LAST_SUCCESSFUL_SSID_FILE" 2>/dev/null
        return 0
    else
        return 1
    fi
}

load_last_successful_ssid() {
    if [[ -f "$LAST_SUCCESSFUL_SSID_FILE" && -r "$LAST_SUCCESSFUL_SSID_FILE" ]]; then
        LAST_SUCCESSFUL_SSID=$(cat "$LAST_SUCCESSFUL_SSID_FILE" 2>/dev/null || echo "")
    fi
}

# --------------------------
# إدارة القفل المحسنة - مع إصلاح Lock File corruption
# --------------------------

# تنظيف الـ lock files القديمة
cleanup_stale_locks() {
    if [[ -f "$LOCK_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        
        if [[ -n "$old_pid" ]] && ! ps -p "$old_pid" &>/dev/null 2>&1; then
            rm -f "$LOCK_FILE" "$LOCK_FILE.lock" 2>/dev/null
        fi
    fi
    
    # إزالة lock files قديمة (أكثر من 10 دقائق)
    find /tmp -name "aasw.lock*" -type f -mmin +10 -delete 2>/dev/null || true
}

# تنظيف إجباري لملفات القفل
force_cleanup_locks() {
    rm -f "$LOCK_FILE" "$LOCK_FILE.lock" 2>/dev/null
    pkill -f "aasw.sh" 2>/dev/null || true
    sleep 2
}

acquire_lock() {
    local lock_acquired=false
    local attempts=0
    local max_attempts=10
    local lock_fd
    
    # تنظيف الـ lock files القديمة أولاً
    cleanup_stale_locks

    while [[ $attempts -lt $max_attempts ]]; do
        if command -v flock &>/dev/null; then
            # استخدام flock بطريقة آمنة مع file descriptor
            exec 200>"$LOCK_FILE"
            if flock -xn 200; then
                echo "$$" >&200
                log_message "DEBUG" "Lock acquired using flock (PID: $$)" "تم الحصول على القفل باستخدام flock"
                lock_acquired=true
                break
            else
                exec 200>&-  # إغلاق file descriptor عند الفشل
            fi
        else
            # Atomic lock creation مع التحقق من صحة PID
            if (
                set -C
                umask 077  # قفل الصلاحيات
                echo "$$:$(date +%s):$(hostname)" > "$LOCK_FILE"
            ) 2>/dev/null; then
                log_message "DEBUG" "Lock acquired using atomic write (PID: $$)" "تم الحصول على القفل بالكتابة الذرية"
                lock_acquired=true
                break
            elif [[ -f "$LOCK_FILE" ]]; then
                local lock_info old_pid lock_time lock_host
                lock_info=$(cat "$LOCK_FILE" 2>/dev/null)
                
                if [[ -n "$lock_info" ]]; then
                    old_pid=$(echo "$lock_info" | cut -d':' -f1)
                    lock_time=$(echo "$lock_info" | cut -d':' -f2)
                    lock_host=$(echo "$lock_info" | cut -d':' -f3)
                    
                    # التحقق من صحة PID والمضيف
                    if [[ -n "$old_pid" && "$lock_host" == "$(hostname)" ]]; then
                        if ! kill -0 "$old_pid" 2>/dev/null; then
                            log_message "WARN" "Stale lock detected (dead PID: $old_pid), removing" "قفل قديم مكتشف"
                            rm -f "$LOCK_FILE" 2>/dev/null
                            continue
                        else
                            # التحقق من عمر القفل (إذا كان أقدم من ساعة)
                            local current_time=$(date +%s)
                            if [[ -n "$lock_time" && $((current_time - lock_time)) -gt 3600 ]]; then
                                log_message "WARN" "Very old lock detected (age: $((current_time - lock_time))s), forcing removal" "قفل قديم جداً"
                                rm -f "$LOCK_FILE" 2>/dev/null
                                continue
                            fi
                            exit_instance_error "$old_pid"
                        fi
                    else
                        # قفل من مضيف آخر أو غير صالح
                        log_message "WARN" "Invalid lock file format or different host, removing" "ملف قفل غير صالح"
                        rm -f "$LOCK_FILE" 2>/dev/null
                        continue
                    fi
                fi
            fi
        fi
        
        ((attempts++))
        log_message "DEBUG" "Lock attempt $attempts/$max_attempts failed" "محاولة القفل $attempts/$max_attempts فشلت"
        sleep 2
    done

    if ! $lock_acquired; then
        log_message "ERROR" "Failed to acquire lock after $max_attempts attempts - forcing cleanup" \
                   "فشل الحصول على القفل بعد $max_attempts محاولة - تنظيف إجباري"
        force_cleanup_locks
        return 1
    fi
    
    # إنشاء handler للتنظيف عند الخروج
    trap 'release_lock' EXIT
    return 0
}

# إطلاق سراح القفل بطريقة آمنة
release_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_info
        lock_info=$(cat "$LOCK_FILE" 2>/dev/null)
        local lock_pid=$(echo "$lock_info" | cut -d':' -f1 2>/dev/null)
        
        # التأكد أن هذا المعرف يملك القفل
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$LOCK_FILE" 2>/dev/null
            log_message "DEBUG" "Lock released successfully (PID: $$)" "تم إطلاق القفل بنجاح"
        fi
    fi
    
    # إغلاق file descriptor إذا كان مفتوح
    exec 200>&- 2>/dev/null || true
}

# ========================================
# DISPLAY FUNCTIONS - دوال العرض
# ========================================

show_awacs_banner() {
    if [[ "$VERBOSE" == "true" ]]; then
        case "$LANGUAGE" in
            "en")
                echo ""
                echo "  █████╗ ██╗    ██╗ █████╗  ██████╗███████╗"
                echo "  ██╔══██╗██║    ██║██╔══██╗██╔════╝██╔════╝"
                echo "  ███████║██║ █╗ ██║███████║██║     ███████╗"
                echo "  ██╔══██║██║███╗██║██╔══██║██║     ╚════██║"
                echo "  ██║  ██║╚███╔███╔╝██║  ██║╚██████╗███████║"
                echo "  ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝"
                echo ""
                echo "           🛡️ AWACS v1.0 - Always Watching, Always Connected 🛡️"
                echo "               Advanced WiFi Auto Connection System"
                echo ""
                echo "         Device: $DEVICE_NAME ($DEVICE_ID)"
                echo "         Language: $LANGUAGE | Logging: $LOG_MODE | Mode: $SPEED_MODE"
                echo "         Created by: NetStorm - AbuNaif from Kuwait 🇰🇼"
                echo ""
                ;;
            "ar")
                echo ""
                echo "  █████╗ ██╗    ██╗ █████╗  ██████╗███████╗"
                echo "  ██╔══██╗██║    ██║██╔══██╗██╔════╝██╔════╝"
                echo "  ███████║██║ █╗ ██║███████║██║     ███████╗"
                echo "  ██╔══██║██║███╗██║██╔══██║██║     ╚════██║"
                echo "  ██║  ██║╚███╔███╔╝██║  ██║╚██████╗███████║"
                echo "  ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝"
                echo ""
                echo "           🛡️ أواكس v1.0 - مراقبة دائمة، اتصال مستمر 🛡️"
                echo "               أنظمة واي فاي التلقائية كاملة السيطرة"
                echo ""
                echo "         الجهاز: $DEVICE_NAME ($DEVICE_ID)"
                echo "         اللغة: $LANGUAGE | التسجيل: $LOG_MODE | الوضع: $SPEED_MODE"
                echo "         بواسطة: نت ستورم - أبونايف (محمد المطيري) من الكويت 🇰🇼"
                echo ""
                ;;
            "both")
                echo ""
                echo "  █████╗ ██╗    ██╗ █████╗  ██████╗███████╗"
                echo "  ██╔══██╗██║    ██║██╔══██╗██╔════╝██╔════╝"
                echo "  ███████║██║ █╗ ██║███████║██║     ███████╗"
                echo "  ██╔══██║██║███╗██║██╔══██║██║     ╚════██║"
                echo "  ██║  ██║╚███╔███╔╝██║  ██║╚██████╗███████║"
                echo "  ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝"
                echo ""
                echo "    🛡️ AWACS v1.0 - Always Watching, Always Connected 🛡️"
                echo "    🛡️ أواكس v1.0 - مراقبة دائمة، اتصال مستمر 🛡️"
                echo "         Advanced WiFi Auto Connection System"
                echo "         أنظمة واي فاي التلقائية كاملة السيطرة"
                echo ""
                echo "         Device: $DEVICE_NAME ($DEVICE_ID) | الجهاز: $DEVICE_NAME ($DEVICE_ID)"
                echo "         Language: $LANGUAGE | Mode: $SPEED_MODE | Logging: $LOG_MODE"
                echo "         اللغة: $LANGUAGE | الوضع: $SPEED_MODE | التسجيل: $LOG_MODE"
                echo "         Created by: NetStorm - AbuNaif (Kuwait) | بواسطة: نت ستورم - أبونايف (الكويت) 🇰🇼"
                echo ""
                ;;
        esac
    fi
}

show_help_message() {
    case "$LANGUAGE" in
        "en")
            echo "=== AWACS v1.0 - Advanced WiFi Auto Connection System ==="
            echo "Always Watching, Always Connected"
            echo ""
            echo "Usage: $0 [options] [command]"
            echo ""
            echo "Performance Mode Options:"
            echo "  --performance    - High performance mode (60s recovery)"
            echo "  --balanced       - Balanced mode (90s recovery) - DEFAULT"
            echo "  --stability      - Maximum stability mode (155s recovery)"
            echo ""
            echo "Language Options:"
            echo "  --lang-en        - English interface only"
            echo "  --lang-ar        - Arabic interface only"
            echo "  --lang-both      - Bilingual interface - DEFAULT"
            echo ""
            echo "Logging Options:"
            echo "  --log-local      - Local logging only - DEFAULT"
            echo "  --log-remote     - Remote logging only"
            echo "  --log-both       - Local and remote logging"
            echo "  --log-none       - No logging"
            echo ""
            echo "System Options:"
            echo "  -d, --daemon     - Run in daemon mode"
            echo "  -v, --verbose    - Verbose output - DEFAULT"
            echo "  -q, --quiet      - Quiet operation"
            echo ""
            echo "Available Commands:"
            echo "  status           - Show current network status"
            echo "  evaluate_networks- Evaluate and score available networks"
            echo "  find_best_network- Find the best available network"
            echo "  measure_speed    - Measure current connection speed"
            echo "  scan_networks    - Scan and show available networks"
            echo "  check_internet   - Check internet connectivity"
            echo "  help            - Show this help message"
            echo ""
            echo "File Path Configuration:"
            echo "  Edit these variables at the top of the script:"
            echo "  CUSTOM_WORK_DIR=\"/path/to/work\"     # Custom work directory"
            echo "  CUSTOM_LOG_DIR=\"/path/to/logs\"      # Custom log directory"
            echo "  CUSTOM_TEMP_DIR=\"/path/to/temp\"     # Custom temp directory"
            echo "  CUSTOM_CONFIG_DIR=\"/path/to/config\" # Custom config directory"
            echo "  Leave empty for default (beside script)"
            echo ""
            echo "Examples:"
            echo "  $0 --performance --lang-en    # High performance, English only"
            echo "  $0 --stability --daemon       # Maximum stability, daemon mode"
            echo "  $0 --lang-ar status           # Arabic interface, show status"
            ;;
        "ar")
            echo "=== أواكس v1.0 - أنظمة واي فاي التلقائية كاملة السيطرة ==="
            echo "مراقبة دائمة، اتصال مستمر"
            echo ""
            echo "الاستخدام: $0 [خيارات] [أمر]"
            echo ""
            echo "خيارات وضع الأداء:"
            echo "  --performance    - وضع الأداء العالي (استرداد 60 ثانية)"
            echo "  --balanced       - الوضع المتوازن (استرداد 90 ثانية) - افتراضي"
            echo "  --stability      - وضع الاستقرار الأقصى (استرداد 155 ثانية)"
            echo ""
            echo "خيارات اللغة:"
            echo "  --lang-en        - واجهة إنجليزية فقط"
            echo "  --lang-ar        - واجهة عربية فقط"
            echo "  --lang-both      - واجهة ثنائية اللغة - افتراضي"
            echo ""
            echo "خيارات التسجيل:"
            echo "  --log-local      - تسجيل محلي فقط - افتراضي"
            echo "  --log-remote     - تسجيل بعيد فقط"
            echo "  --log-both       - تسجيل محلي وبعيد"
            echo "  --log-none       - بدون تسجيل"
            echo ""
            echo "خيارات النظام:"
            echo "  -d, --daemon     - تشغيل في وضع الخدمة"
            echo "  -v, --verbose    - إخراج مفصل - افتراضي"
            echo "  -q, --quiet      - تشغيل هادئ"
            echo ""
            echo "الأوامر المتاحة:"
            echo "  status           - عرض حالة الشبكة الحالية"
            echo "  evaluate_networks- تقييم وتسجيل الشبكات المتاحة"
            echo "  find_best_network- العثور على أفضل شبكة متاحة"
            echo "  measure_speed    - قياس سرعة الاتصال الحالية"
            echo "  scan_networks    - فحص وعرض الشبكات المتاحة"
            echo "  check_internet   - فحص الاتصال بالإنترنت"
            echo "  help            - عرض رسالة المساعدة هذه"
            echo ""
            echo "تكوين مسارات الملفات:"
            echo "  عدّل هذه المتغيرات في أعلى السكريبت:"
            echo "  CUSTOM_WORK_DIR=\"/مسار/للعمل\"       # مجلد العمل المخصص"
            echo "  CUSTOM_LOG_DIR=\"/مسار/للسجلات\"      # مجلد السجلات المخصص"
            echo "  CUSTOM_TEMP_DIR=\"/مسار/للمؤقت\"      # مجلد الملفات المؤقتة المخصص"
            echo "  CUSTOM_CONFIG_DIR=\"/مسار/للتكوين\"   # مجلد التكوين المخصص"
            echo "  اتركها فارغة للافتراضي (جانب السكريبت)"
            echo ""
            echo "أمثلة:"
            echo "  $0 --performance --lang-ar    # أداء عالي، عربي فقط"
            echo "  $0 --stability --daemon       # استقرار أقصى، وضع خدمة"
            echo "  $0 --lang-en status           # واجهة إنجليزية، عرض الحالة"
            ;;
        "both")
            echo "=== AWACS v1.0 - Advanced WiFi Auto Connection System ==="
            echo "=== أواكس v1.0 - أنظمة واي فاي التلقائية كاملة السيطرة ==="
            echo "Always Watching, Always Connected | مراقبة دائمة، اتصال مستمر"
            echo ""
            echo "Usage: $0 [options] [command] | الاستخدام: $0 [خيارات] [أمر]"
            echo ""
            echo "Performance Mode | وضع الأداء: --performance (عالي), --balanced (متوازن), --stability (مستقر)"
            echo "Language | اللغة: --lang-en (إنجليزي), --lang-ar (عربي), --lang-both (كلاهما)"
            echo "Logging | التسجيل: --log-local (محلي), --log-remote (بعيد), --log-both (كلاهما)"
            echo "System | النظام: --daemon (خدمة), --verbose (مفصل), --quiet (هادئ)"
            echo ""
            echo "File Paths | مسارات الملفات: Edit CUSTOM_*_DIR variables | عدّل متغيرات CUSTOM_*_DIR"
            echo ""
            echo "Examples | أمثلة:"
            echo "  $0 --performance --lang-both  # High performance, bilingual"
            echo "  $0 --stability --daemon       # Max stability, daemon mode"
            ;;
    esac
}

# ========================================
# GRACEFUL DEGRADATION SYSTEM - نظام التدهور التدريجي
# ========================================

# متغيرات نظام التدهور التدريجي
declare -g DEGRADATION_LEVEL=0
declare -g CONSECUTIVE_FAILURES=0
declare -g LAST_SUCCESSFUL_CONNECTION=0
declare -g DEGRADATION_ACTIVE=false

# مستويات التدهور التدريجي
# Level 0: Normal operation | تشغيل عادي
# Level 1: Reduced frequency | تقليل التكرار  
# Level 2: Emergency mode | وضع الطوارئ
# Level 3: Survival mode | وضع البقاء

apply_graceful_degradation() {
    local failure_count="$1"
    local last_success_age="$2"
    local current_time=$(date +%s)
    
    # حساب العمر منذ آخر اتصال ناجح (بالثواني)
    if [[ "$last_success_age" -eq 0 ]]; then
        last_success_age=$((current_time - LAST_SUCCESSFUL_CONNECTION))
    fi
    
    local new_degradation_level=0
    
    # تحديد مستوى التدهور بناءً على الأخطاء والوقت
    if ((failure_count >= 3 && last_success_age > 300)); then
        new_degradation_level=1  # 5+ دقائق بدون اتصال
    fi
    
    if ((failure_count >= 6 && last_success_age > 900)); then
        new_degradation_level=2  # 15+ دقيقة بدون اتصال
    fi
    
    if ((failure_count >= 10 && last_success_age > 1800)); then
        new_degradation_level=3  # 30+ دقيقة بدون اتصال
    fi
    
    # تطبيق التدهور فقط إذا كان هناك تغيير
    if [[ "$new_degradation_level" != "$DEGRADATION_LEVEL" ]]; then
        DEGRADATION_LEVEL="$new_degradation_level"
        
        case "$DEGRADATION_LEVEL" in
            0)
                log_message "SUCCESS" "Returning to normal operation mode" "العودة لوضع التشغيل العادي"
                DEGRADATION_ACTIVE=false
                # استعادة القيم الأصلية
                configure_speed_mode
                ;;
                
            1)
                log_message "WARN" "Entering reduced frequency mode (Level 1)" "دخول وضع التكرار المنخفض (مستوى 1)"
                DEGRADATION_ACTIVE=true
                # تقليل التكرار بـ 50%
                CHECK_INTERVAL=$((CHECK_INTERVAL * 2))
                SCAN_INTERVAL=$((SCAN_INTERVAL * 2))
                ;;
                
            2)
                log_message "WARN" "Entering emergency mode (Level 2)" "دخول وضع الطوارئ (مستوى 2)"
                DEGRADATION_ACTIVE=true
                # تقليل التكرار بـ 75%
                CHECK_INTERVAL=$((CHECK_INTERVAL * 4))
                SCAN_INTERVAL=$((SCAN_INTERVAL * 3))
                # تعطيل الميزات غير الضرورية
                CONSERVE_RESOURCES="yes"
                AUTO_CONNECT_OPEN="no"
                ;;
                
            3)
                log_message "ERROR" "Entering survival mode (Level 3)" "دخول وضع البقاء (مستوى 3)"
                DEGRADATION_ACTIVE=true
                # تقليل التكرار إلى الحد الأدنى
                CHECK_INTERVAL=60
                SCAN_INTERVAL=120
                # تعطيل جميع الميزات الإضافية
                CONSERVE_RESOURCES="yes"
                AUTO_CONNECT_OPEN="no"
                CONNECT_HIDDEN="no"
                STEALTH_MODE="yes"
                # تقليل timeout values
                SWITCH_TIMEOUT=2
                ;;
        esac
        
        log_message "INFO" "Degradation applied - Level: $DEGRADATION_LEVEL, Check: ${CHECK_INTERVAL}s, Scan: ${SCAN_INTERVAL}s" \
                   "تم تطبيق التدهور - مستوى: $DEGRADATION_LEVEL، فحص: ${CHECK_INTERVAL}ث، مسح: ${SCAN_INTERVAL}ث"
    fi
}

# استعادة الحالة العادية عند نجاح الاتصال
restore_normal_operation() {
    CONSECUTIVE_FAILURES=0
    LAST_SUCCESSFUL_CONNECTION=$(date +%s)
    
    if [[ "$DEGRADATION_ACTIVE" == "true" ]]; then
        log_message "SUCCESS" "Connection restored, checking if normal operation can be resumed" \
                   "تم استعادة الاتصال، فحص إمكانية العودة للتشغيل العادي"
        
        # تطبيق تدهور مع القيم الجديدة
        apply_graceful_degradation 0 0
    fi
}

# فحص دوري لحالة التدهور
monitor_degradation_status() {
    local current_time=$(date +%s)
    local time_since_success=$((current_time - LAST_SUCCESSFUL_CONNECTION))
    
    # إذا مر وقت طويل منذ آخر فحص للتدهور
    if ((time_since_success % 300 == 0 && time_since_success > 0)); then
        log_message "DEBUG" "Degradation status - Level: $DEGRADATION_LEVEL, Failures: $CONSECUTIVE_FAILURES, Time since success: ${time_since_success}s" \
                   "حالة التدهور - مستوى: $DEGRADATION_LEVEL، أخطاء: $CONSECUTIVE_FAILURES، الوقت منذ النجاح: ${time_since_success}ث"
    fi
}

# --------------------------
# الدالة الرئيسية
# --------------------------

main() {
    # Show startup banner | عرض شعار البدء
    show_awacs_banner
    
    # تهيئة متغيرات التدهور التدريجي
    LAST_SUCCESSFUL_CONNECTION=$(date +%s)
    
    log_message "INFO" "Starting AWACS v1.0 (Ultra-Stable)" "بدء أواكس v1.0 (فائق الاستقرار)"
    
    # تشغيل التحقق من صحة التكوين
    if ! validate_configuration; then
        log_message "ERROR" "Configuration validation failed, exiting" "فشل التحقق من التكوين، خروج"
        exit 1
    fi
    
    # إعلام وضع السرعة المفعّل
    case "$SPEED_MODE" in
        "fast")
            log_message "INFO" "Fast mode activated - prioritizes speed over stability" \
                       "تم تفعيل الوضع السريع - يفضل السرعة على الاستقرار"
            ;;
        "balanced")
            log_message "INFO" "Balanced mode activated - optimal speed/stability balance" \
                       "تم تفعيل الوضع المتوازن - توازن مثالي بين السرعة والاستقرار"
            ;;
        "conservative")
            log_message "INFO" "Conservative mode activated - prioritizes stability over speed" \
                       "تم تفعيل الوضع المحافظ - يفضل الاستقرار على السرعة"
            ;;
    esac
    
    check_dependencies
    if ! detect_wifi_interfaces; then
        log_message "ERROR" "Failed to detect WiFi interfaces, attempting hardware recovery" \
                   "فشل اكتشاف واجهات WiFi، محاولة إصلاح الأجهزة"
        if ! recover_from_failure; then
            log_message "ERROR" "WiFi hardware recovery failed, system may need reboot" \
                       "فشل إصلاح أجهزة WiFi، قد يحتاج النظام لإعادة تشغيل"
            sudo reboot
            exit 1
        fi
        # إعادة المحاولة بعد الإصلاح
        if ! detect_wifi_interfaces; then
            log_message "ERROR" "WiFi interfaces still not available after recovery" \
                       "واجهات WiFi ما زالت غير متاحة بعد الإصلاح"
            sudo reboot
            exit 1
        fi
    fi
    setup_temp_files
    load_last_successful_ssid
    check_wpa_supplicant_status
    
    if ! check_wifi_hardware; then
        log_message "ERROR" "WiFi hardware issues detected, attempting recovery" \
                   "تم اكتشاف مشاكل في أجهزة الواي فاي، محاولة الإصلاح"
        recover_from_failure
        sleep 5
    fi
    
    manage_stored_networks
    
    if [[ "$CONNECT_HIDDEN" == "yes" ]]; then
        handle_hidden_networks
    fi
    
    enable_stealth_mode
    
    local current_ssid
    current_ssid=$(get_current_ssid)
    
    if [[ -z "$current_ssid" ]]; then
        log_message "INFO" "No network connection, searching for available networks" \
                   "لا يوجد اتصال بشبكة، جاري البحث عن شبكات متاحة"
        aggressive_connect
    elif ! check_internet; then
        log_message "WARN" "Connected to $current_ssid but no internet access, trying alternative networks" \
                   "متصل بـ $current_ssid ولكن لا يوجد اتصال بالإنترنت، محاولة شبكات بديلة"
        aggressive_connect
    else
        log_message "SUCCESS" "Already connected to $current_ssid with internet access" \
                   "متصل بالفعل بـ $current_ssid مع وجود اتصال بالإنترنت"
        LAST_SUCCESSFUL_SSID="$current_ssid"
        save_last_successful_ssid "$current_ssid"
        adjust_scan_interval 1
    fi
    
    SYSTEM_BOOTING=false
    
    local failure_count=0
    local consecutive_success=0
    local last_cleanup=$(date +%s)
    
    > "$LAST_SCAN_FILE"
    
    while true; do
        check_night_mode
        
        local current_time=$(date +%s)
        if ((current_time - last_cleanup >= 3600)); then
            cleanup_temp_files
            last_cleanup=$current_time
        fi
        
        if ! check_wifi_hardware; then
            log_message "ERROR" "Hardware issue detected, attempting recovery" \
                       "تم اكتشاف مشكلة في الأجهزة، محاولة الإصلاح"
            recover_from_failure
        fi
        
        if ((RANDOM % 10 == 0)); then
            check_wpa_supplicant_status
        fi
        
        if test_and_optimize_connection; then
            INTERNET_CONNECTED=true
            failure_count=0
            ((consecutive_success++))
            
            # استعادة الحالة العادية عند نجاح الاتصال
            restore_normal_operation
            
            adjust_scan_interval 1
            
            if ((consecutive_success >= 5)); then
                upload_pending_logs
                consecutive_success=0
            fi
        else
            INTERNET_CONNECTED=false
            ((failure_count++))
            consecutive_success=0
            CONSECUTIVE_FAILURES=$failure_count
            
            # تطبيق التدهور التدريجي
            apply_graceful_degradation "$failure_count" 0
            
            adjust_scan_interval 0
            
            log_message "ERROR" "Internet connection lost (Attempt $failure_count/$MAX_FAILURES)" \
                      "فقدان الاتصال بالإنترنت (محاولة $failure_count من $MAX_FAILURES)"
            
            if ((failure_count >= MAX_FAILURES)); then
                if [[ -n "$LAST_SUCCESSFUL_SSID" ]]; then
                    log_message "INFO" "Final attempt: Trying to reconnect to last successful network ($LAST_SUCCESSFUL_SSID) before reboot" \
                  "المحاولة الأخيرة: إعادة الاتصال بآخر شبكة ناجحة ($LAST_SUCCESSFUL_SSID) قبل إعادة التشغيل"
        
                    if connect_to_network "$LAST_SUCCESSFUL_SSID"; then
                        if check_internet; then
                            local speed
                            speed=$(measure_speed)
                
                            if compare_float "$speed" ">" "$MIN_SPEED"; then
                                log_message "SUCCESS" "Successfully reconnected to $LAST_SUCCESSFUL_SSID with acceptable speed (${speed}Mbps)" \
                               "تم إعادة الاتصال بنجاح بشبكة $LAST_SUCCESSFUL_SSID بسرعة مقبولة (${speed}Mbps)"
                                failure_count=0
                                INTERNET_CONNECTED=true
                                consecutive_success=1
                                continue
                            fi
                        fi
                    fi
                fi
            
                log_message "ERROR" "Maximum failures reached, rebooting system" \
                          "تم الوصول للحد الأقصى من المحاولات، جاري إعادة تشغيل النظام"
                sync
                sleep 2
                sudo reboot
            fi
            
            log_message "INFO" "Attempting to reconnect..." "محاولة إعادة الاتصال..."
            
            if aggressive_connect; then
                if check_internet; then
                    failure_count=0
                    log_message "SUCCESS" "Successfully reconnected to network" "تم إعادة الاتصال بالشبكة بنجاح"
                fi
            fi
        fi
        
        # مراقبة حالة التدهور
        monitor_degradation_status
        
        sleep "$CHECK_INTERVAL"
    done
}

# دالة تشغيل الأوامر
run_function() {
    case "$1" in
        "status")
            check_dependencies no_restart
            detect_wifi_interfaces
            local current_ssid
            current_ssid=$(get_current_ssid)
            local internet_status
            internet_status=$(check_internet && echo "Available ✓" || echo "Not available ✗")

            log_message "INFO" "=== Network Status ===" "=== حالة الشبكة ==="
            log_message "INFO" "Current network: ${current_ssid:-Not connected}" "الشبكة الحالية: ${current_ssid:-غير متصل}"
            log_message "INFO" "Internet connection: $internet_status" "الاتصال بالإنترنت: $internet_status"
            
            if [[ "$internet_status" == "Available ✓" ]]; then
                local speed
                speed=$(measure_speed)
                log_message "INFO" "Connection speed: ${speed}Mbps" "سرعة الاتصال: ${speed}Mbps"
            fi
            ;;
        "evaluate_networks")
            check_dependencies no_restart
            detect_wifi_interfaces
            log_message "INFO" "Evaluating available networks" "تقييم الشبكات المتاحة"
            local scan_results
            scan_results=$(scan_networks)
            if [[ -n "$scan_results" ]]; then
                local networks_info
                networks_info=$(analyze_available_networks "$scan_results")
                if [[ -n "$networks_info" ]]; then
                    echo "=== Network Analysis ==="
                    while IFS="|" read -r ssid signal speed score is_current priority; do
                        [[ -z "$ssid" ]] && continue
                        local status=""
                        [[ "$is_current" == "1" ]] && status=" (Current ✓)"
                        echo "SSID: $ssid | Signal: ${signal}dBm | Est.Speed: ${speed}Mbps | Score: $score | Priority: $priority$status"
                    done <<< "$networks_info"
                fi
            fi
            ;;
        "find_best_network")
            check_dependencies no_restart
            detect_wifi_interfaces
            local best_network
            best_network=$(find_best_network)
            if [[ -n "$best_network" ]]; then
                log_message "SUCCESS" "Best network found: $best_network" "تم العثور على أفضل شبكة: $best_network"
            else
                log_message "INFO" "Current network is optimal" "الشبكة الحالية مثلى"
            fi
            ;;
        "measure_speed")
            check_dependencies no_restart
            detect_wifi_interfaces
            local speed
            speed=$(measure_speed)
            log_message "SUCCESS" "Current connection speed: ${speed}Mbps" "سرعة الاتصال الحالية: ${speed}Mbps"
            ;;
        "scan_networks")
            check_dependencies no_restart
            detect_wifi_interfaces
            log_message "INFO" "Scanning for available networks" "البحث عن الشبكات المتاحة"
            local scan_results
            scan_results=$(scan_networks)
            
            if [[ -n "$scan_results" ]]; then
                log_message "SUCCESS" "Network scan completed" "اكتمل مسح الشبكات"
                echo "=== Available Networks ==="
                echo "$scan_results" | while IFS=$'\t' read -r bssid ssid signal; do
                    echo "SSID: $ssid | Signal: $signal | BSSID: $bssid"
                done
            else
                log_message "WARN" "No networks found" "لم يتم العثور على شبكات"
            fi
            ;;
        "check_internet")
            check_dependencies no_restart
            if check_internet; then
                log_message "SUCCESS" "Internet connection: Available ✓" "الاتصال بالإنترنت: متوفر ✓"
            else
                log_message "ERROR" "Internet connection: Not available ✗" "الاتصال بالإنترنت: غير متوفر ✗"
            fi
            ;;
        "help"|"--help"|"-h")
            show_help_message
            log_message "INFO" "Usage: $0 [options] [command]" "الاستخدام: $0 [خيارات] [أمر]"
            echo ""
            echo "Speed Mode Options:"
            echo "  --fast           - Fast mode (60s to reboot) - less stability"
            echo "  --balanced       - Balanced mode (90s to reboot) - DEFAULT"
            echo "  --conservative   - Conservative mode (155s to reboot) - max stability"
            echo ""
            echo "Available commands:"
            echo "  status           - Show current network status"
            echo "  evaluate_networks- Evaluate and score available networks"
            echo "  find_best_network- Find the best available network"
            echo "  measure_speed    - Measure current connection speed"
            echo "  scan_networks    - Scan and show available networks"
            echo "  check_internet   - Check internet connectivity"
            echo "  help            - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --fast        # Run in fast mode"
            echo "  $0 --conservative status  # Check status in conservative mode"
            ;;
        *)
            log_message "ERROR" "Unknown command: $1" "أمر غير معروف: $1"
            log_message "INFO" "Use '$0 help' for available commands" "استخدم '$0 help' للأوامر المتاحة"
            return 1
            ;;
    esac
}

# نقطة الدخول الرئيسية
if [[ -n "$1" ]]; then
    run_function "$1"
    exit $?
fi

# الحصول على القفل مع معالجة الأخطاء
if ! acquire_lock; then
    log_message "ERROR" "Another instance is running or lock acquisition failed" \
               "يوجد تشغيل آخر أو فشل الحصول على القفل"
    exit 1
fi

main
