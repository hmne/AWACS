#!/bin/bash
# ===================================================
# AWACS Interactive Installer | مثبت أواكس التفاعلي
# Advanced WiFi Auto Connection System
# ===================================================

# set -e removed to allow interactive input

# Colors and visual effects | ألوان وتأثيرات بصرية
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
BLINK='\033[5m'
REVERSE='\033[7m'
NC='\033[0m' # No Color

# Global settings | إعدادات عامة
INSTALL_LANGUAGE="en"
SETUP_MODE="simple"
INSTALL_DIR="/opt/awacs"
GITHUB_REPO="https://github.com/hmne/awacs"
TEMP_DIR="/tmp/awacs-install"

# Configuration variables | متغيرات التكوين
CONFIG_LANGUAGE="both"
CONFIG_LOG_MODE="local"
CONFIG_SPEED_MODE="balanced"
CONFIG_DEVICE_ID="AWACS-1"
CONFIG_DEVICE_NAME="AWACS WiFi Manager"
CONFIG_DEFAULT_DIR_NAME="awacs"
CONFIG_CUSTOM_WORK_DIR=""
CONFIG_CUSTOM_LOG_DIR=""
CONFIG_CUSTOM_TEMP_DIR=""
CONFIG_CUSTOM_CONFIG_DIR=""
CONFIG_REMOTE_LOGGING="no"
CONFIG_REMOTE_URL=""
CONFIG_AUTO_CONNECT_OPEN="yes"
CONFIG_CONNECT_HIDDEN="yes"
CONFIG_NIGHT_MODE="yes"
CONFIG_STEALTH_MODE="no"
CONFIG_CREATE_SERVICE="yes"
CONFIG_START_NOW="yes"

# ===============================================
# VISUAL FUNCTIONS | دوال الواجهة البصرية
# ===============================================

# Clear screen with style | مسح الشاشة بأناقة
clear_screen() {
    clear
    printf '\033[H\033[2J'
}

# Print animated header | عرض رأس متحرك
show_animated_header() {
    clear_screen
    echo ""
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        echo -e "${CYAN}${BOLD}"
        echo "  █████╗ ██╗    ██╗ █████╗  ██████╗███████╗"
        echo "  ██╔══██╗██║    ██║██╔══██╗██╔════╝██╔════╝"
        echo "  ███████║██║ █╗ ██║███████║██║     ███████╗"
        echo "  ██╔══██║██║███╗██║██╔══██║██║     ╚════██║"
        echo "  ██║  ██║╚███╔███╔╝██║  ██║╚██████╗███████║"
        echo "  ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝"
        echo -e "${NC}"
        echo ""
        echo -e "${WHITE}${BOLD}           🛡️ مراقبة دائمة، اتصال مستمر 🛡️${NC}"
        echo -e "${YELLOW}        أنظمة واي فاي التلقائية كاملة السيطرة${NC}"
        echo -e "${GREEN}       بواسطة نت ستورم - أبونايف من الكويت 🇰🇼${NC}"
    else
        echo -e "${CYAN}${BOLD}"
        echo "  █████╗ ██╗    ██╗ █████╗  ██████╗███████╗"
        echo "  ██╔══██╗██║    ██║██╔══██╗██╔════╝██╔════╝"
        echo "  ███████║██║ █╗ ██║███████║██║     ███████╗"
        echo "  ██╔══██║██║███╗██║██╔══██║██║     ╚════██║"
        echo "  ██║  ██║╚███╔███╔╝██║  ██║╚██████╗███████║"
        echo "  ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝"
        echo -e "${NC}"
        echo ""
        echo -e "${WHITE}${BOLD}           🛡️ Always Watching, Always Connected 🛡️${NC}"
        echo -e "${YELLOW}         Advanced WiFi Auto Connection System${NC}"
        echo -e "${GREEN}        Created by NetStorm - AbuNaif from Kuwait 🇰🇼${NC}"
    fi
    echo ""
    echo -e "${PURPLE}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Print section header | عرض رأس القسم
print_section() {
    echo ""
    echo -e "${BLUE}${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}${BOLD}│${NC} ${WHITE}${BOLD}$1${NC} ${BLUE}${BOLD}│${NC}"
    echo -e "${BLUE}${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Print option | عرض خيار
print_option() {
    local number="$1"
    local text="$2"
    local desc="$3"
    echo -e "${YELLOW}${BOLD}[$number]${NC} ${WHITE}$text${NC}"
    if [[ -n "$desc" ]]; then
        echo -e "     ${DIM}$desc${NC}"
    fi
}

# Print current setting | عرض الإعداد الحالي  
print_current() {
    local label="$1"
    local value="$2"
    echo -e "${CYAN}${BOLD}►${NC} ${label}: ${GREEN}${BOLD}$value${NC}"
}

# Print progress bar | عرض شريط التقدم
show_progress() {
    local current="$1"
    local total="$2"
    local text="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}${BOLD}Progress: ${NC}["
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] ${GREEN}${BOLD}%d%%${NC} - ${WHITE}%s${NC}" $percent "$text"
}

# Wait for user input with style | انتظار إدخال المستخدم بأناقة
wait_input() {
    echo ""
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        echo -e "${PURPLE}${BOLD}اختر رقم الخيار المطلوب: ${NC}"
    else
        echo -e "${PURPLE}${BOLD}Select option number: ${NC}"
    fi
    echo -n -e "${YELLOW}${BOLD}► ${NC}"
    
    # Use timeout to prevent hanging
    if ! read -r -t 300 USER_INPUT; then
        echo ""
        echo -e "${YELLOW}${BOLD}No input received, using default...${NC}"
        USER_INPUT=""
    fi
}

# ===============================================
# LANGUAGE SELECTION | اختيار اللغة
# ===============================================

select_language() {
    show_animated_header
    
    echo -e "${WHITE}${BOLD}🌍 Language Selection | اختيار اللغة${NC}"
    echo ""
    echo -e "${DIM}Choose your preferred language for the installer${NC}"
    echo -e "${DIM}اختر لغتك المفضلة للمثبت${NC}"
    echo ""
    
    print_option "1" "English" "Full English interface and messages"
    print_option "2" "العربية" "واجهة وأرائل باللغة العربية بالكامل"
    print_option "3" "Bilingual | ثنائي اللغة" "Both languages (recommended)"
    
    echo ""
    echo -e "${GREEN}${BOLD}Default: 3 (Bilingual) - Press Enter for default${NC}"
    
    wait_input
    
    case "$USER_INPUT" in
        "1") 
            INSTALL_LANGUAGE="en"
            ;;
        "2") 
            INSTALL_LANGUAGE="ar"
            ;;
        "3"|"") 
            INSTALL_LANGUAGE="both"
            ;;
        *)
            INSTALL_LANGUAGE="both"
            ;;
    esac
}

# ===============================================
# SETUP MODE SELECTION | اختيار وضع الإعداد
# ===============================================

select_setup_mode() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "🛠️ وضع الإعداد"
        echo -e "${DIM}اختر مستوى الإعداد المطلوب${NC}"
        echo ""
        
        print_option "1" "إعداد بسيط (مستحسن)" "إعداد سريع مع الخيارات الافتراضية المثلى"
        print_option "2" "إعداد متقدم" "تخصيص كامل لجميع الخيارات والإعدادات"
        
        echo ""
        echo -e "${GREEN}${BOLD}الافتراضي: 1 (بسيط) - اضغط Enter للافتراضي${NC}"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "🛠️ Setup Mode"
        echo -e "${DIM}Choose your preferred setup level${NC}"
        echo ""
        
        print_option "1" "Simple Setup (Recommended)" "Quick setup with optimal default settings"
        print_option "2" "Advanced Setup" "Full customization of all options and settings"
        
        echo ""
        echo -e "${GREEN}${BOLD}Default: 1 (Simple) - Press Enter for default${NC}"
        
    else
        print_section "🛠️ Setup Mode | وضع الإعداد"
        echo -e "${DIM}Choose your preferred setup level | اختر مستوى الإعداد المطلوب${NC}"
        echo ""
        
        print_option "1" "Simple Setup | إعداد بسيط" "Quick setup with optimal defaults | إعداد سريع مع الخيارات المثلى"
        print_option "2" "Advanced Setup | إعداد متقدم" "Full customization | تخصيص كامل لجميع الخيارات"
        
        echo ""
        echo -e "${GREEN}${BOLD}Default: 1 (Simple) | الافتراضي: 1 (بسيط) - Press Enter | اضغط Enter${NC}"
    fi
    
    wait_input
    
    case "$USER_INPUT" in
        "1"|"") 
            SETUP_MODE="simple"
            ;;
        "2") 
            SETUP_MODE="advanced"
            ;;
        *)
            SETUP_MODE="simple"
            ;;
    esac
}

# ===============================================
# SIMPLE SETUP | الإعداد البسيط
# ===============================================

simple_setup() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "⚡ الإعداد السريع"
        echo -e "${GREEN}سيتم تطبيق الإعدادات الافتراضية المثلى:${NC}"
        echo ""
        print_current "اللغة" "ثنائي اللغة (إنجليزي + عربي)"
        print_current "وضع الأداء" "متوازن (90 ثانية)"
        print_current "التسجيل" "محلي فقط"
        print_current "مجلد الملفات" "awacs/ (جانب السكريبت)"
        print_current "الاتصال التلقائي" "مفعل"
        print_current "إنشاء خدمة" "نعم"
        
        echo ""
        print_option "1" "متابعة مع هذه الإعدادات" "تثبيت مع الإعدادات الافتراضية"
        print_option "2" "الانتقال للإعداد المتقدم" "تخصيص جميع الخيارات"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "⚡ Quick Setup"
        echo -e "${GREEN}Optimal default settings will be applied:${NC}"
        echo ""
        print_current "Language" "Bilingual (English + Arabic)"
        print_current "Performance" "Balanced (90 seconds)"
        print_current "Logging" "Local only"
        print_current "File Directory" "awacs/ (beside script)"
        print_current "Auto Connect" "Enabled"
        print_current "Create Service" "Yes"
        
        echo ""
        print_option "1" "Continue with these settings" "Install with default configuration"
        print_option "2" "Switch to Advanced Setup" "Customize all options"
        
    else
        print_section "⚡ Quick Setup | الإعداد السريع"
        echo -e "${GREEN}Optimal default settings will be applied | سيتم تطبيق الإعدادات المثلى:${NC}"
        echo ""
        print_current "Language | اللغة" "Bilingual | ثنائي اللغة"
        print_current "Performance | الأداء" "Balanced | متوازن"
        print_current "Logging | التسجيل" "Local only | محلي فقط"
        print_current "Directory | المجلد" "awacs/ (beside script | جانب السكريبت)"
        print_current "Auto Connect | الاتصال التلقائي" "Enabled | مفعل"
        print_current "Create Service | إنشاء خدمة" "Yes | نعم"
        
        echo ""
        print_option "1" "Continue | متابعة" "Install with defaults | تثبيت مع الافتراضي"
        print_option "2" "Advanced Setup | إعداد متقدم" "Customize all | تخصيص الكل"
    fi
    
    wait_input
    
    case "$USER_INPUT" in
        "1"|"") 
            return 0
            ;;
        "2") 
            SETUP_MODE="advanced"
            advanced_setup
            ;;
        *)
            return 0
            ;;
    esac
}

# ===============================================
# ADVANCED SETUP FUNCTIONS | دوال الإعداد المتقدم
# ===============================================

configure_language() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "🌍 إعداد اللغة"
        echo -e "${DIM}اختر لغة واجهة السكريبت والسجلات${NC}"
        echo ""
        print_option "1" "إنجليزي فقط" "واجهة وسجلات إنجليزية بالكامل"
        print_option "2" "عربي فقط" "واجهة وسجلات عربية بالكامل"
        print_option "3" "ثنائي اللغة (مستحسن)" "واجهة وسجلات بكلا اللغتين"
        echo ""
        echo -e "${GREEN}${BOLD}الافتراضي: 3 (ثنائي) - اضغط Enter للافتراضي${NC}"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "🌍 Language Configuration"
        echo -e "${DIM}Choose the script interface and logging language${NC}"
        echo ""
        print_option "1" "English Only" "Full English interface and logs"
        print_option "2" "Arabic Only" "Full Arabic interface and logs"
        print_option "3" "Bilingual (Recommended)" "Both languages interface and logs"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 3 (Bilingual) - Press Enter for default${NC}"
        
    else
        print_section "🌍 Language Configuration | إعداد اللغة"
        echo -e "${DIM}Choose interface and logging language | اختر لغة الواجهة والسجلات${NC}"
        echo ""
        print_option "1" "English Only | إنجليزي فقط" "Full English | إنجليزية بالكامل"
        print_option "2" "Arabic Only | عربي فقط" "Full Arabic | عربية بالكامل"
        print_option "3" "Bilingual | ثنائي اللغة" "Both languages | كلا اللغتين (Recommended | مستحسن)"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 3 (Bilingual) | الافتراضي: 3 (ثنائي) - Press Enter | اضغط Enter${NC}"
    fi
    
    wait_input
    
    case "$USER_INPUT" in
        "1") CONFIG_LANGUAGE="en" ;;
        "2") CONFIG_LANGUAGE="ar" ;;
        "3"|"") CONFIG_LANGUAGE="both" ;;
        *) CONFIG_LANGUAGE="both" ;;
    esac
}

configure_performance() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "⚡ إعداد الأداء"
        echo -e "${DIM}اختر وضع الأداء حسب احتياجاتك${NC}"
        echo ""
        print_option "1" "سريع (60 ثانية)" "أداء عالي، مناسب للألعاب والبث (استهلاك طاقة أعلى)"
        print_option "2" "متوازن (90 ثانية)" "توازن مثالي بين الأداء والاستقرار (مستحسن)"
        print_option "3" "مستقر (155 ثانية)" "أقصى استقرار، مناسب للأنظمة الحيوية (استهلاك طاقة أقل)"
        echo ""
        echo -e "${GREEN}${BOLD}الافتراضي: 2 (متوازن) - اضغط Enter للافتراضي${NC}"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "⚡ Performance Configuration"
        echo -e "${DIM}Choose performance mode based on your needs${NC}"
        echo ""
        print_option "1" "Fast (60 seconds)" "High performance, ideal for gaming/streaming (higher power)"
        print_option "2" "Balanced (90 seconds)" "Optimal balance between performance and stability (recommended)"
        print_option "3" "Stable (155 seconds)" "Maximum stability, ideal for critical systems (lower power)"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 2 (Balanced) - Press Enter for default${NC}"
        
    else
        print_section "⚡ Performance Configuration | إعداد الأداء"
        echo -e "${DIM}Choose performance mode | اختر وضع الأداء${NC}"
        echo ""
        print_option "1" "Fast | سريع (60s)" "High performance | أداء عالي - Gaming/streaming | ألعاب/بث"
        print_option "2" "Balanced | متوازن (90s)" "Optimal balance | توازن مثالي (Recommended | مستحسن)"
        print_option "3" "Stable | مستقر (155s)" "Maximum stability | أقصى استقرار - Critical systems | أنظمة حيوية"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 2 (Balanced) | الافتراضي: 2 (متوازن) - Press Enter | اضغط Enter${NC}"
    fi
    
    wait_input
    
    case "$USER_INPUT" in
        "1") CONFIG_SPEED_MODE="fast" ;;
        "2"|"") CONFIG_SPEED_MODE="balanced" ;;
        "3") CONFIG_SPEED_MODE="conservative" ;;
        *) CONFIG_SPEED_MODE="balanced" ;;
    esac
}

configure_logging() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "📊 إعداد السجلات"
        echo -e "${DIM}اختر كيفية حفظ سجلات النظام${NC}"
        echo ""
        print_option "1" "محلي فقط" "حفظ السجلات محلياً في نفس مجلد السكريبت (مستحسن)"
        print_option "2" "بعيد فقط" "إرسال السجلات لخادم بعيد فقط (يتطلب إعداد URL)"
        print_option "3" "محلي + بعيد" "حفظ السجلات محلياً وإرسالها للخادم البعيد"
        print_option "4" "بدون سجلات" "عدم حفظ أي سجلات (أقل استهلاك، غير مستحسن)"
        echo ""
        echo -e "${GREEN}${BOLD}الافتراضي: 1 (محلي) - اضغط Enter للافتراضي${NC}"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "📊 Logging Configuration"
        echo -e "${DIM}Choose how to handle system logs${NC}"
        echo ""
        print_option "1" "Local Only" "Save logs locally in script directory (recommended)"
        print_option "2" "Remote Only" "Send logs to remote server only (requires URL setup)"
        print_option "3" "Local + Remote" "Save logs locally and send to remote server"
        print_option "4" "No Logging" "Disable all logging (minimal footprint, not recommended)"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 1 (Local) - Press Enter for default${NC}"
        
    else
        print_section "📊 Logging Configuration | إعداد السجلات"
        echo -e "${DIM}Choose logging method | اختر طريقة التسجيل${NC}"
        echo ""
        print_option "1" "Local Only | محلي فقط" "Save locally | حفظ محلي (Recommended | مستحسن)"
        print_option "2" "Remote Only | بعيد فقط" "Send to server | إرسال للخادم"
        print_option "3" "Local + Remote | محلي + بعيد" "Both methods | كلا الطريقتين"
        print_option "4" "No Logging | بدون سجلات" "Disable logs | تعطيل السجلات"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 1 (Local) | الافتراضي: 1 (محلي) - Press Enter | اضغط Enter${NC}"
    fi
    
    wait_input
    
    case "$USER_INPUT" in
        "1"|"") CONFIG_LOG_MODE="local" ;;
        "2") 
            CONFIG_LOG_MODE="remote"
            CONFIG_REMOTE_LOGGING="yes"
            configure_remote_url
            ;;
        "3") 
            CONFIG_LOG_MODE="both"
            CONFIG_REMOTE_LOGGING="yes"
            configure_remote_url
            ;;
        "4") CONFIG_LOG_MODE="none" ;;
        *) CONFIG_LOG_MODE="local" ;;
    esac
}

configure_remote_url() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "🌐 رابط الخادم البعيد"
        echo -e "${DIM}أدخل رابط الخادم البعيد لإرسال السجلات${NC}"
        echo ""
        echo -e "${YELLOW}مثال: http://your-server.com/awacs${NC}"
        echo -e "${YELLOW}مثال: https://logs.mycompany.com/api/awacs${NC}"
        echo ""
        echo -e "${WHITE}${BOLD}أدخل رابط الخادم (أو اضغط Enter للتخطي):${NC}"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "🌐 Remote Server URL"
        echo -e "${DIM}Enter the remote server URL for sending logs${NC}"
        echo ""
        echo -e "${YELLOW}Example: http://your-server.com/awacs${NC}"
        echo -e "${YELLOW}Example: https://logs.mycompany.com/api/awacs${NC}"
        echo ""
        echo -e "${WHITE}${BOLD}Enter server URL (or Press Enter to skip):${NC}"
        
    else
        print_section "🌐 Remote Server URL | رابط الخادم البعيد"
        echo -e "${DIM}Enter remote server URL | أدخل رابط الخادم البعيد${NC}"
        echo ""
        echo -e "${YELLOW}Example | مثال: http://your-server.com/awacs${NC}"
        echo -e "${YELLOW}Example | مثال: https://logs.mycompany.com/api/awacs${NC}"
        echo ""
        echo -e "${WHITE}${BOLD}Enter URL | أدخل الرابط (Press Enter to skip | اضغط Enter للتخطي):${NC}"
    fi
    
    echo -n -e "${YELLOW}${BOLD}► ${NC}"
    read -r CONFIG_REMOTE_URL
    
    if [[ -z "$CONFIG_REMOTE_URL" ]]; then
        CONFIG_REMOTE_LOGGING="no"
        CONFIG_LOG_MODE="local"
    fi
}

configure_directories() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "📁 إعداد المجلدات"
        echo -e "${DIM}اختر كيفية تنظيم ملفات السكريبت${NC}"
        echo ""
        print_option "1" "افتراضي (مستحسن)" "إنشاء مجلد 'awacs' جانب السكريبت"
        print_option "2" "اسم مجلد مخصص" "تخصيص اسم المجلد جانب السكريبت"
        print_option "3" "مسارات مخصصة" "تخصيص مسارات كاملة للملفات"
        echo ""
        echo -e "${GREEN}${BOLD}الافتراضي: 1 (افتراضي) - اضغط Enter للافتراضي${NC}"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "📁 Directory Configuration"
        echo -e "${DIM}Choose how to organize script files${NC}"
        echo ""
        print_option "1" "Default (Recommended)" "Create 'awacs' folder beside script"
        print_option "2" "Custom Folder Name" "Customize folder name beside script"
        print_option "3" "Custom Paths" "Full customization of file paths"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 1 (Default) - Press Enter for default${NC}"
        
    else
        print_section "📁 Directory Configuration | إعداد المجلدات"
        echo -e "${DIM}Choose file organization | اختر تنظيم الملفات${NC}"
        echo ""
        print_option "1" "Default | افتراضي" "Create 'awacs' folder | إنشاء مجلد 'awacs' (Recommended | مستحسن)"
        print_option "2" "Custom Name | اسم مخصص" "Customize folder name | تخصيص اسم المجلد"
        print_option "3" "Custom Paths | مسارات مخصصة" "Full path customization | تخصيص مسارات كامل"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 1 | الافتراضي: 1 - Press Enter | اضغط Enter${NC}"
    fi
    
    wait_input
    
    case "$USER_INPUT" in
        "1"|"") 
            # Keep defaults
            ;;
        "2") 
            configure_custom_folder_name
            ;;
        "3") 
            configure_custom_paths
            ;;
        *) 
            # Keep defaults
            ;;
    esac
}

configure_custom_folder_name() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "📂 اسم المجلد المخصص"
        echo -e "${DIM}أدخل اسم المجلد المطلوب إنشاؤه جانب السكريبت${NC}"
        echo ""
        echo -e "${YELLOW}أمثلة: my-wifi, network-manager, wifi-awacs${NC}"
        echo -e "${YELLOW}الحالي: awacs${NC}"
        echo ""
        echo -e "${WHITE}${BOLD}أدخل اسم المجلد (أو اضغط Enter لـ 'awacs'):${NC}"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "📂 Custom Folder Name"
        echo -e "${DIM}Enter the folder name to create beside the script${NC}"
        echo ""
        echo -e "${YELLOW}Examples: my-wifi, network-manager, wifi-awacs${NC}"
        echo -e "${YELLOW}Current: awacs${NC}"
        echo ""
        echo -e "${WHITE}${BOLD}Enter folder name (or Press Enter for 'awacs'):${NC}"
        
    else
        print_section "📂 Custom Folder Name | اسم المجلد المخصص"
        echo -e "${DIM}Enter folder name | أدخل اسم المجلد${NC}"
        echo ""
        echo -e "${YELLOW}Examples | أمثلة: my-wifi, network-manager, wifi-awacs${NC}"
        echo -e "${YELLOW}Current | الحالي: awacs${NC}"
        echo ""
        echo -e "${WHITE}${BOLD}Enter name | أدخل الاسم (Press Enter for 'awacs' | اضغط Enter لـ 'awacs'):${NC}"
    fi
    
    echo -n -e "${YELLOW}${BOLD}► ${NC}"
    read -r custom_name
    
    if [[ -n "$custom_name" ]]; then
        # Validate folder name
        if [[ "$custom_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            CONFIG_DEFAULT_DIR_NAME="$custom_name"
        else
            echo -e "${RED}Invalid folder name. Using default 'awacs'${NC}"
            sleep 2
        fi
    fi
}

configure_custom_paths() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "🗂️ المسارات المخصصة"
        echo -e "${DIM}تخصيص مسارات كاملة للملفات (اتركها فارغة للافتراضي)${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}مجلد العمل الرئيسي:${NC}"
        echo -e "${DIM}مثال: /home/user/my-awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_WORK_DIR
        
        echo -e "${WHITE}${BOLD}مجلد السجلات:${NC}"
        echo -e "${DIM}مثال: /var/log/awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_LOG_DIR
        
        echo -e "${WHITE}${BOLD}مجلد الملفات المؤقتة:${NC}"
        echo -e "${DIM}مثال: /tmp/awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_TEMP_DIR
        
        echo -e "${WHITE}${BOLD}مجلد التكوين:${NC}"
        echo -e "${DIM}مثال: /etc/awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_CONFIG_DIR
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "🗂️ Custom Paths"
        echo -e "${DIM}Customize full file paths (leave empty for defaults)${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}Main Work Directory:${NC}"
        echo -e "${DIM}Example: /home/user/my-awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_WORK_DIR
        
        echo -e "${WHITE}${BOLD}Log Directory:${NC}"
        echo -e "${DIM}Example: /var/log/awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_LOG_DIR
        
        echo -e "${WHITE}${BOLD}Temporary Files Directory:${NC}"
        echo -e "${DIM}Example: /tmp/awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_TEMP_DIR
        
        echo -e "${WHITE}${BOLD}Configuration Directory:${NC}"
        echo -e "${DIM}Example: /etc/awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_CONFIG_DIR
        
    else
        print_section "🗂️ Custom Paths | المسارات المخصصة"
        echo -e "${DIM}Customize paths (leave empty for defaults) | تخصيص المسارات (اتركها فارغة للافتراضي)${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}Work Directory | مجلد العمل:${NC}"
        echo -e "${DIM}Example | مثال: /home/user/my-awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_WORK_DIR
        
        echo -e "${WHITE}${BOLD}Log Directory | مجلد السجلات:${NC}"
        echo -e "${DIM}Example | مثال: /var/log/awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_LOG_DIR
        
        echo -e "${WHITE}${BOLD}Temp Directory | مجلد مؤقت:${NC}"
        echo -e "${DIM}Example | مثال: /tmp/awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_TEMP_DIR
        
        echo -e "${WHITE}${BOLD}Config Directory | مجلد التكوين:${NC}"
        echo -e "${DIM}Example | مثال: /etc/awacs${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r CONFIG_CUSTOM_CONFIG_DIR
    fi
}

configure_device() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "🏷️ معرف الجهاز"
        echo -e "${DIM}تخصيص معرف واسم الجهاز${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}معرف الجهاز (Device ID):${NC}"
        echo -e "${DIM}مثال: AWACS-HOME, AWACS-OFFICE, PI-CAMERA-01${NC}"
        echo -e "${YELLOW}الحالي: AWACS-1${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r device_id
        
        echo -e "${WHITE}${BOLD}اسم الجهاز (Device Name):${NC}"
        echo -e "${DIM}مثال: Home WiFi Manager, Office Network Controller${NC}"
        echo -e "${YELLOW}الحالي: AWACS WiFi Manager${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r device_name
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "🏷️ Device Identity"
        echo -e "${DIM}Customize device ID and name${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}Device ID:${NC}"
        echo -e "${DIM}Example: AWACS-HOME, AWACS-OFFICE, PI-CAMERA-01${NC}"
        echo -e "${YELLOW}Current: AWACS-1${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r device_id
        
        echo -e "${WHITE}${BOLD}Device Name:${NC}"
        echo -e "${DIM}Example: Home WiFi Manager, Office Network Controller${NC}"
        echo -e "${YELLOW}Current: AWACS WiFi Manager${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r device_name
        
    else
        print_section "🏷️ Device Identity | معرف الجهاز"
        echo -e "${DIM}Customize device info | تخصيص معلومات الجهاز${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}Device ID | معرف الجهاز:${NC}"
        echo -e "${DIM}Example | مثال: AWACS-HOME, PI-CAMERA-01${NC}"
        echo -e "${YELLOW}Current | الحالي: AWACS-1${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r device_id
        
        echo -e "${WHITE}${BOLD}Device Name | اسم الجهاز:${NC}"
        echo -e "${DIM}Example | مثال: Home WiFi Manager${NC}"
        echo -e "${YELLOW}Current | الحالي: AWACS WiFi Manager${NC}"
        echo -n -e "${YELLOW}► ${NC}"
        read -r device_name
    fi
    
    if [[ -n "$device_id" ]]; then
        CONFIG_DEVICE_ID="$device_id"
    fi
    
    if [[ -n "$device_name" ]]; then
        CONFIG_DEVICE_NAME="$device_name"
    fi
}

configure_network_options() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "📡 خيارات الشبكة"
        echo -e "${DIM}تخصيص سلوك الاتصال بالشبكات${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}الاتصال التلقائي بالشبكات المفتوحة:${NC}"
        print_option "1" "نعم (مستحسن)" "الاتصال تلقائياً بالشبكات المفتوحة المتاحة"
        print_option "2" "لا" "عدم الاتصال بالشبكات المفتوحة"
        echo -n -e "${YELLOW}► ${NC}"
        read -r auto_connect
        
        echo -e "${WHITE}${BOLD}البحث عن الشبكات المخفية:${NC}"
        print_option "1" "نعم (مستحسن)" "البحث والاتصال بالشبكات المخفية"
        print_option "2" "لا" "تجاهل الشبكات المخفية"
        echo -n -e "${YELLOW}► ${NC}"
        read -r hidden_networks
        
        echo -e "${WHITE}${BOLD}وضع الليل (توفير الطاقة):${NC}"
        print_option "1" "نعم (مستحسن)" "تقليل استهلاك الطاقة في فترات الليل"
        print_option "2" "لا" "عمل عادي طوال اليوم"
        echo -n -e "${YELLOW}► ${NC}"
        read -r night_mode
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "📡 Network Options"
        echo -e "${DIM}Customize network connection behavior${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}Auto-connect to open networks:${NC}"
        print_option "1" "Yes (Recommended)" "Automatically connect to available open networks"
        print_option "2" "No" "Do not connect to open networks"
        echo -n -e "${YELLOW}► ${NC}"
        read -r auto_connect
        
        echo -e "${WHITE}${BOLD}Search for hidden networks:${NC}"
        print_option "1" "Yes (Recommended)" "Search and connect to hidden networks"
        print_option "2" "No" "Ignore hidden networks"
        echo -n -e "${YELLOW}► ${NC}"
        read -r hidden_networks
        
        echo -e "${WHITE}${BOLD}Night mode (power saving):${NC}"
        print_option "1" "Yes (Recommended)" "Reduce power consumption during night hours"
        print_option "2" "No" "Normal operation all day"
        echo -n -e "${YELLOW}► ${NC}"
        read -r night_mode
        
    else
        print_section "📡 Network Options | خيارات الشبكة"
        echo -e "${DIM}Customize network behavior | تخصيص سلوك الشبكة${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}Auto-connect to open networks | الاتصال التلقائي بالشبكات المفتوحة:${NC}"
        print_option "1" "Yes | نعم" "(Recommended | مستحسن)"
        print_option "2" "No | لا" "Skip open networks | تجاهل الشبكات المفتوحة"
        echo -n -e "${YELLOW}► ${NC}"
        read -r auto_connect
        
        echo -e "${WHITE}${BOLD}Search hidden networks | البحث عن الشبكات المخفية:${NC}"
        print_option "1" "Yes | نعم" "(Recommended | مستحسن)"
        print_option "2" "No | لا" "Ignore hidden | تجاهل المخفية"
        echo -n -e "${YELLOW}► ${NC}"
        read -r hidden_networks
        
        echo -e "${WHITE}${BOLD}Night mode | وضع الليل:${NC}"
        print_option "1" "Yes | نعم" "Power saving | توفير طاقة (Recommended | مستحسن)"
        print_option "2" "No | لا" "Normal operation | تشغيل عادي"
        echo -n -e "${YELLOW}► ${NC}"
        read -r night_mode
    fi
    
    case "$auto_connect" in
        "1"|"") CONFIG_AUTO_CONNECT_OPEN="yes" ;;
        "2") CONFIG_AUTO_CONNECT_OPEN="no" ;;
    esac
    
    case "$hidden_networks" in
        "1"|"") CONFIG_CONNECT_HIDDEN="yes" ;;
        "2") CONFIG_CONNECT_HIDDEN="no" ;;
    esac
    
    case "$night_mode" in
        "1"|"") CONFIG_NIGHT_MODE="yes" ;;
        "2") CONFIG_NIGHT_MODE="no" ;;
    esac
}

configure_service() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "🚀 إعداد الخدمة"
        echo -e "${DIM}تخصيص خيارات تشغيل الخدمة${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}إنشاء خدمة نظام (systemd):${NC}"
        print_option "1" "نعم (مستحسن)" "إنشاء خدمة تعمل تلقائياً عند تشغيل النظام"
        print_option "2" "لا" "تشغيل يدوي فقط"
        echo -n -e "${YELLOW}► ${NC}"
        read -r create_service
        
        if [[ "$create_service" != "2" ]]; then
            echo -e "${WHITE}${BOLD}تشغيل الخدمة الآن:${NC}"
            print_option "1" "نعم (مستحسن)" "بدء تشغيل AWACS فوراً بعد التثبيت"
            print_option "2" "لا" "تشغيل يدوي لاحقاً"
            echo -n -e "${YELLOW}► ${NC}"
            read -r start_now
        fi
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "🚀 Service Configuration"
        echo -e "${DIM}Customize service startup options${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}Create system service (systemd):${NC}"
        print_option "1" "Yes (Recommended)" "Create service to start automatically on boot"
        print_option "2" "No" "Manual operation only"
        echo -n -e "${YELLOW}► ${NC}"
        read -r create_service
        
        if [[ "$create_service" != "2" ]]; then
            echo -e "${WHITE}${BOLD}Start service now:${NC}"
            print_option "1" "Yes (Recommended)" "Start AWACS immediately after installation"
            print_option "2" "No" "Manual start later"
            echo -n -e "${YELLOW}► ${NC}"
            read -r start_now
        fi
        
    else
        print_section "🚀 Service Configuration | إعداد الخدمة"
        echo -e "${DIM}Customize service options | تخصيص خيارات الخدمة${NC}"
        echo ""
        
        echo -e "${WHITE}${BOLD}Create system service | إنشاء خدمة نظام:${NC}"
        print_option "1" "Yes | نعم" "Auto-start on boot | تشغيل تلقائي (Recommended | مستحسن)"
        print_option "2" "No | لا" "Manual operation | تشغيل يدوي"
        echo -n -e "${YELLOW}► ${NC}"
        read -r create_service
        
        if [[ "$create_service" != "2" ]]; then
            echo -e "${WHITE}${BOLD}Start now | تشغيل الآن:${NC}"
            print_option "1" "Yes | نعم" "Start immediately | تشغيل فوري (Recommended | مستحسن)"
            print_option "2" "No | لا" "Start later | تشغيل لاحقاً"
            echo -n -e "${YELLOW}► ${NC}"
            read -r start_now
        fi
    fi
    
    case "$create_service" in
        "1"|"") CONFIG_CREATE_SERVICE="yes" ;;
        "2") CONFIG_CREATE_SERVICE="no" ;;
    esac
    
    case "$start_now" in
        "1"|"") CONFIG_START_NOW="yes" ;;
        "2") CONFIG_START_NOW="no" ;;
    esac
}

# Advanced setup main function | دالة الإعداد المتقدم الرئيسية
advanced_setup() {
    configure_language
    configure_performance
    configure_logging
    configure_directories
    configure_device
    configure_network_options
    configure_service
}

# ===============================================
# CONFIGURATION SUMMARY | ملخص التكوين
# ===============================================

show_configuration_summary() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "📋 ملخص التكوين"
        echo -e "${GREEN}سيتم تطبيق الإعدادات التالية:${NC}"
        echo ""
        
        echo -e "${CYAN}${BOLD}الإعدادات الأساسية:${NC}"
        print_current "اللغة" "$CONFIG_LANGUAGE"
        print_current "وضع الأداء" "$CONFIG_SPEED_MODE"
        print_current "التسجيل" "$CONFIG_LOG_MODE"
        
        echo ""
        echo -e "${CYAN}${BOLD}معلومات الجهاز:${NC}"
        print_current "معرف الجهاز" "$CONFIG_DEVICE_ID"
        print_current "اسم الجهاز" "$CONFIG_DEVICE_NAME"
        
        echo ""
        echo -e "${CYAN}${BOLD}المجلدات:${NC}"
        if [[ -n "$CONFIG_CUSTOM_WORK_DIR" ]]; then
            print_current "مجلد العمل" "$CONFIG_CUSTOM_WORK_DIR"
        else
            print_current "مجلد العمل" "script_dir/$CONFIG_DEFAULT_DIR_NAME/"
        fi
        
        echo ""
        echo -e "${CYAN}${BOLD}خيارات الشبكة:${NC}"
        print_current "الاتصال التلقائي" "$CONFIG_AUTO_CONNECT_OPEN"
        print_current "الشبكات المخفية" "$CONFIG_CONNECT_HIDDEN"
        print_current "وضع الليل" "$CONFIG_NIGHT_MODE"
        
        echo ""
        echo -e "${CYAN}${BOLD}الخدمة:${NC}"
        print_current "إنشاء خدمة" "$CONFIG_CREATE_SERVICE"
        print_current "تشغيل فوري" "$CONFIG_START_NOW"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "📋 Configuration Summary"
        echo -e "${GREEN}The following settings will be applied:${NC}"
        echo ""
        
        echo -e "${CYAN}${BOLD}Basic Settings:${NC}"
        print_current "Language" "$CONFIG_LANGUAGE"
        print_current "Performance Mode" "$CONFIG_SPEED_MODE"
        print_current "Logging" "$CONFIG_LOG_MODE"
        
        echo ""
        echo -e "${CYAN}${BOLD}Device Information:${NC}"
        print_current "Device ID" "$CONFIG_DEVICE_ID"
        print_current "Device Name" "$CONFIG_DEVICE_NAME"
        
        echo ""
        echo -e "${CYAN}${BOLD}Directories:${NC}"
        if [[ -n "$CONFIG_CUSTOM_WORK_DIR" ]]; then
            print_current "Work Directory" "$CONFIG_CUSTOM_WORK_DIR"
        else
            print_current "Work Directory" "script_dir/$CONFIG_DEFAULT_DIR_NAME/"
        fi
        
        echo ""
        echo -e "${CYAN}${BOLD}Network Options:${NC}"
        print_current "Auto Connect" "$CONFIG_AUTO_CONNECT_OPEN"
        print_current "Hidden Networks" "$CONFIG_CONNECT_HIDDEN"
        print_current "Night Mode" "$CONFIG_NIGHT_MODE"
        
        echo ""
        echo -e "${CYAN}${BOLD}Service:${NC}"
        print_current "Create Service" "$CONFIG_CREATE_SERVICE"
        print_current "Start Now" "$CONFIG_START_NOW"
        
    else
        print_section "📋 Configuration Summary | ملخص التكوين"
        echo -e "${GREEN}Settings to apply | الإعدادات المطبقة:${NC}"
        echo ""
        
        echo -e "${CYAN}${BOLD}Basic Settings | الإعدادات الأساسية:${NC}"
        print_current "Language | اللغة" "$CONFIG_LANGUAGE"
        print_current "Performance | الأداء" "$CONFIG_SPEED_MODE"
        print_current "Logging | التسجيل" "$CONFIG_LOG_MODE"
        
        echo ""
        echo -e "${CYAN}${BOLD}Device Info | معلومات الجهاز:${NC}"
        print_current "Device ID | معرف الجهاز" "$CONFIG_DEVICE_ID"
        print_current "Device Name | اسم الجهاز" "$CONFIG_DEVICE_NAME"
        
        echo ""
        echo -e "${CYAN}${BOLD}Directories | المجلدات:${NC}"
        if [[ -n "$CONFIG_CUSTOM_WORK_DIR" ]]; then
            print_current "Work Directory | مجلد العمل" "$CONFIG_CUSTOM_WORK_DIR"
        else
            print_current "Work Directory | مجلد العمل" "script_dir/$CONFIG_DEFAULT_DIR_NAME/"
        fi
        
        echo ""
        echo -e "${CYAN}${BOLD}Network | الشبكة:${NC}"
        print_current "Auto Connect | اتصال تلقائي" "$CONFIG_AUTO_CONNECT_OPEN"
        print_current "Hidden Networks | شبكات مخفية" "$CONFIG_CONNECT_HIDDEN"
        print_current "Night Mode | وضع الليل" "$CONFIG_NIGHT_MODE"
        
        echo ""
        echo -e "${CYAN}${BOLD}Service | الخدمة:${NC}"
        print_current "Create Service | إنشاء خدمة" "$CONFIG_CREATE_SERVICE"
        print_current "Start Now | تشغيل الآن" "$CONFIG_START_NOW"
    fi
    
    echo ""
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_option "1" "متابعة التثبيت" "تطبيق هذه الإعدادات والمتابعة"
        print_option "2" "تعديل الإعدادات" "العودة لتعديل الإعدادات"
        echo ""
        echo -e "${GREEN}${BOLD}الافتراضي: 1 (متابعة) - اضغط Enter للمتابعة${NC}"
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_option "1" "Continue Installation" "Apply these settings and proceed"
        print_option "2" "Modify Settings" "Go back to modify settings"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 1 (Continue) - Press Enter to proceed${NC}"
    else
        print_option "1" "Continue | متابعة" "Apply settings | تطبيق الإعدادات"
        print_option "2" "Modify | تعديل" "Go back | العودة للتعديل"
        echo ""
        echo -e "${GREEN}${BOLD}Default: 1 (Continue) | الافتراضي: 1 (متابعة) - Press Enter | اضغط Enter${NC}"
    fi
    
    wait_input
    
    case "$USER_INPUT" in
        "1"|"") 
            return 0
            ;;
        "2") 
            if [[ "$SETUP_MODE" == "advanced" ]]; then
                advanced_setup
            else
                select_setup_mode
            fi
            show_configuration_summary
            ;;
        *)
            return 0
            ;;
    esac
}

# ===============================================
# INSTALLATION FUNCTIONS | دوال التثبيت
# ===============================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        show_animated_header
        if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
            echo -e "${RED}${BOLD}خطأ: يجب تشغيل المثبت بصلاحيات الجذر${NC}"
            echo -e "${YELLOW}استخدم: curl -fsSL https://raw.githubusercontent.com/hmne/awacs/main/install.sh | sudo bash${NC}"
        elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
            echo -e "${RED}${BOLD}Error: This installer must be run as root${NC}"
            echo -e "${YELLOW}Use: curl -fsSL https://raw.githubusercontent.com/hmne/awacs/main/install.sh | sudo bash${NC}"
        else
            echo -e "${RED}${BOLD}Error: Root required | خطأ: مطلوب صلاحيات الجذر${NC}"
            echo -e "${YELLOW}Use | استخدم: curl -fsSL https://raw.githubusercontent.com/hmne/awacs/main/install.sh | sudo bash${NC}"
        fi
        exit 1
    fi
}

check_requirements() {
    local step=1
    local total_steps=4
    
    show_progress $step $total_steps "Checking system requirements"
    
    # Check required commands
    local missing_commands=()
    for cmd in curl wget git bash; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    step=$((step + 1))
    show_progress $step $total_steps "Installing missing packages"
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "${missing_commands[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y "${missing_commands[@]}"
        elif command -v pacman &> /dev/null; then
            pacman -S --noconfirm "${missing_commands[@]}"
        fi
    fi
    
    step=$((step + 1))
    show_progress $step $total_steps "Checking WiFi support"
    
    # Check WiFi support
    if ! command -v iwconfig &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            apt-get install -y wireless-tools
        fi
    fi
    
    step=$((step + 1))
    show_progress $step $total_steps "Requirements check completed"
    
    echo ""
}

download_awacs() {
    local step=1
    local total_steps=3
    
    show_progress $step $total_steps "Preparing download"
    
    # Create temp directory
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    step=$((step + 1))
    show_progress $step $total_steps "Downloading AWACS"
    
    # Download using git if available
    if command -v git &> /dev/null; then
        git clone "$GITHUB_REPO.git" . || {
            curl -fsSL "$GITHUB_REPO/archive/main.tar.gz" | tar -xz --strip-components=1
        }
    else
        curl -fsSL "$GITHUB_REPO/archive/main.tar.gz" | tar -xz --strip-components=1
    fi
    
    step=$((step + 1))
    show_progress $step $total_steps "Download completed"
    
    echo ""
}

apply_configuration() {
    local step=1
    local total_steps=6
    
    show_progress $step $total_steps "Applying configuration"
    
    # Apply configuration to awacs.sh
    sed -i "s/LANGUAGE=\"both\"/LANGUAGE=\"$CONFIG_LANGUAGE\"/" awacs.sh
    sed -i "s/LOG_MODE=\"local\"/LOG_MODE=\"$CONFIG_LOG_MODE\"/" awacs.sh
    sed -i "s/SPEED_MODE=\"balanced\"/SPEED_MODE=\"$CONFIG_SPEED_MODE\"/" awacs.sh
    sed -i "s/DEVICE_ID=\"AWACS-1\"/DEVICE_ID=\"$CONFIG_DEVICE_ID\"/" awacs.sh
    sed -i "s/DEVICE_NAME=\"AWACS WiFi Manager\"/DEVICE_NAME=\"$CONFIG_DEVICE_NAME\"/" awacs.sh
    sed -i "s/DEFAULT_DIR_NAME=\"awacs\"/DEFAULT_DIR_NAME=\"$CONFIG_DEFAULT_DIR_NAME\"/" awacs.sh
    
    step=$((step + 1))
    show_progress $step $total_steps "Configuring paths"
    
    if [[ -n "$CONFIG_CUSTOM_WORK_DIR" ]]; then
        sed -i "s|CUSTOM_WORK_DIR=\"\"|CUSTOM_WORK_DIR=\"$CONFIG_CUSTOM_WORK_DIR\"|" awacs.sh
    fi
    
    if [[ -n "$CONFIG_CUSTOM_LOG_DIR" ]]; then
        sed -i "s|CUSTOM_LOG_DIR=\"\"|CUSTOM_LOG_DIR=\"$CONFIG_CUSTOM_LOG_DIR\"|" awacs.sh
    fi
    
    step=$((step + 1))
    show_progress $step $total_steps "Configuring remote logging"
    
    sed -i "s/REMOTE_LOGGING=\"no\"/REMOTE_LOGGING=\"$CONFIG_REMOTE_LOGGING\"/" awacs.sh
    if [[ -n "$CONFIG_REMOTE_URL" ]]; then
        sed -i "s|REMOTE_URL=\"\"|REMOTE_URL=\"$CONFIG_REMOTE_URL\"|" awacs.sh
    fi
    
    step=$((step + 1))
    show_progress $step $total_steps "Configuring network options"
    
    sed -i "s/AUTO_CONNECT_OPEN=\"yes\"/AUTO_CONNECT_OPEN=\"$CONFIG_AUTO_CONNECT_OPEN\"/" awacs.sh
    sed -i "s/CONNECT_HIDDEN=\"yes\"/CONNECT_HIDDEN=\"$CONFIG_CONNECT_HIDDEN\"/" awacs.sh
    sed -i "s/NIGHT_MODE=\"yes\"/NIGHT_MODE=\"$CONFIG_NIGHT_MODE\"/" awacs.sh
    
    step=$((step + 1))
    show_progress $step $total_steps "Installing files"
    
    # Install files
    mkdir -p "$INSTALL_DIR"
    cp awacs.sh "$INSTALL_DIR/"
    cp README.md LICENSE CHANGELOG.md "$INSTALL_DIR/" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/awacs.sh"
    ln -sf "$INSTALL_DIR/awacs.sh" "/usr/local/bin/awacs"
    
    step=$((step + 1))
    show_progress $step $total_steps "Configuration completed"
    
    echo ""
}

create_service() {
    if [[ "$CONFIG_CREATE_SERVICE" != "yes" ]]; then
        return 0
    fi
    
    local step=1
    local total_steps=3
    
    show_progress $step $total_steps "Creating systemd service"
    
    cat > "/etc/systemd/system/awacs.service" << EOF
[Unit]
Description=AWACS - Advanced WiFi Auto Connection System
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/awacs.sh --daemon --$CONFIG_SPEED_MODE --lang-$CONFIG_LANGUAGE
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    step=$((step + 1))
    show_progress $step $total_steps "Enabling service"
    
    systemctl daemon-reload
    systemctl enable awacs
    
    step=$((step + 1))
    show_progress $step $total_steps "Service created"
    
    echo ""
}

start_service() {
    if [[ "$CONFIG_START_NOW" != "yes" || "$CONFIG_CREATE_SERVICE" != "yes" ]]; then
        return 0
    fi
    
    local step=1
    local total_steps=2
    
    show_progress $step $total_steps "Starting AWACS service"
    
    systemctl start awacs
    
    step=$((step + 1))
    show_progress $step $total_steps "Service started"
    
    echo ""
}

cleanup() {
    rm -rf "$TEMP_DIR"
}

# ===============================================
# INSTALLATION SUMMARY | ملخص التثبيت
# ===============================================

show_installation_summary() {
    show_animated_header
    
    if [[ "$INSTALL_LANGUAGE" == "ar" ]]; then
        print_section "🎉 تم التثبيت بنجاح!"
        echo -e "${GREEN}${BOLD}تم تثبيت أواكس بنجاح مع التكوين المطلوب${NC}"
        echo ""
        
        echo -e "${CYAN}${BOLD}معلومات التثبيت:${NC}"
        print_current "مجلد التثبيت" "$INSTALL_DIR"
        print_current "أمر التشغيل" "awacs"
        if [[ "$CONFIG_CREATE_SERVICE" == "yes" ]]; then
            print_current "خدمة النظام" "awacs"
            print_current "حالة الخدمة" "$(systemctl is-active awacs 2>/dev/null || echo 'متوقفة')"
        fi
        
        echo ""
        echo -e "${CYAN}${BOLD}الأوامر المتاحة:${NC}"
        echo -e "${YELLOW}# اختبار أواكس${NC}"
        echo -e "${WHITE}awacs --help${NC}"
        echo ""
        echo -e "${YELLOW}# عرض الحالة${NC}"
        echo -e "${WHITE}awacs status${NC}"
        echo ""
        if [[ "$CONFIG_CREATE_SERVICE" == "yes" ]]; then
            echo -e "${YELLOW}# إدارة الخدمة${NC}"
            echo -e "${WHITE}systemctl start awacs${NC}"
            echo -e "${WHITE}systemctl stop awacs${NC}"
            echo -e "${WHITE}systemctl status awacs${NC}"
            echo ""
            echo -e "${YELLOW}# عرض السجلات${NC}"
            echo -e "${WHITE}journalctl -u awacs -f${NC}"
            echo ""
        fi
        
        echo -e "${GREEN}${BOLD}🛡️ أواكس: مراقبة دائمة، اتصال مستمر 🛡️${NC}"
        
    elif [[ "$INSTALL_LANGUAGE" == "en" ]]; then
        print_section "🎉 Installation Successful!"
        echo -e "${GREEN}${BOLD}AWACS has been successfully installed with your configuration${NC}"
        echo ""
        
        echo -e "${CYAN}${BOLD}Installation Information:${NC}"
        print_current "Installation Directory" "$INSTALL_DIR"
        print_current "Global Command" "awacs"
        if [[ "$CONFIG_CREATE_SERVICE" == "yes" ]]; then
            print_current "System Service" "awacs"
            print_current "Service Status" "$(systemctl is-active awacs 2>/dev/null || echo 'stopped')"
        fi
        
        echo ""
        echo -e "${CYAN}${BOLD}Available Commands:${NC}"
        echo -e "${YELLOW}# Test AWACS${NC}"
        echo -e "${WHITE}awacs --help${NC}"
        echo ""
        echo -e "${YELLOW}# Show Status${NC}"
        echo -e "${WHITE}awacs status${NC}"
        echo ""
        if [[ "$CONFIG_CREATE_SERVICE" == "yes" ]]; then
            echo -e "${YELLOW}# Service Management${NC}"
            echo -e "${WHITE}systemctl start awacs${NC}"
            echo -e "${WHITE}systemctl stop awacs${NC}"
            echo -e "${WHITE}systemctl status awacs${NC}"
            echo ""
            echo -e "${YELLOW}# View Logs${NC}"
            echo -e "${WHITE}journalctl -u awacs -f${NC}"
            echo ""
        fi
        
        echo -e "${GREEN}${BOLD}🛡️ AWACS: Always Watching, Always Connected 🛡️${NC}"
        
    else
        print_section "🎉 Installation Successful! | تم التثبيت بنجاح!"
        echo -e "${GREEN}${BOLD}AWACS installed successfully | تم تثبيت أواكس بنجاح${NC}"
        echo ""
        
        echo -e "${CYAN}${BOLD}Installation Info | معلومات التثبيت:${NC}"
        print_current "Directory | المجلد" "$INSTALL_DIR"
        print_current "Command | الأمر" "awacs"
        if [[ "$CONFIG_CREATE_SERVICE" == "yes" ]]; then
            print_current "Service | الخدمة" "awacs"
            print_current "Status | الحالة" "$(systemctl is-active awacs 2>/dev/null || echo 'stopped | متوقفة')"
        fi
        
        echo ""
        echo -e "${CYAN}${BOLD}Commands | الأوامر:${NC}"
        echo -e "${YELLOW}# Test | اختبار${NC}"
        echo -e "${WHITE}awacs --help${NC}"
        echo ""
        echo -e "${YELLOW}# Status | الحالة${NC}"
        echo -e "${WHITE}awacs status${NC}"
        echo ""
        if [[ "$CONFIG_CREATE_SERVICE" == "yes" ]]; then
            echo -e "${YELLOW}# Service | الخدمة${NC}"
            echo -e "${WHITE}systemctl start awacs${NC}"
            echo -e "${WHITE}systemctl status awacs${NC}"
            echo ""
            echo -e "${YELLOW}# Logs | السجلات${NC}"
            echo -e "${WHITE}journalctl -u awacs -f${NC}"
            echo ""
        fi
        
        echo -e "${GREEN}${BOLD}🛡️ AWACS: Always Watching, Always Connected 🛡️${NC}"
        echo -e "${GREEN}${BOLD}🛡️ أواكس: مراقبة دائمة، اتصال مستمر 🛡️${NC}"
    fi
    
    echo ""
    echo -e "${PURPLE}${BOLD}GitHub: ${CYAN}$GITHUB_REPO${NC}"
    echo -e "${PURPLE}${BOLD}Created by NetStorm - AbuNaif from Kuwait 🇰🇼${NC}"
    echo ""
}

# ===============================================
# MAIN INSTALLER FUNCTION | دالة المثبت الرئيسية
# ===============================================

main() {
    # Interactive setup first (doesn't need root)
    select_language
    select_setup_mode
    
    # Check root privileges after user input
    check_root
    
    if [[ "$SETUP_MODE" == "simple" ]]; then
        simple_setup
    else
        advanced_setup
    fi
    
    # Show configuration summary
    show_configuration_summary
    
    # Installation process
    check_requirements
    download_awacs
    apply_configuration
    create_service
    start_service
    cleanup
    
    # Show final summary
    show_installation_summary
}

# Error handling | معالجة الأخطاء
trap 'echo -e "\n${RED}${BOLD}Installation failed | فشل التثبيت${NC}"; cleanup; exit 1' ERR

# Run main installer | تشغيل المثبت الرئيسي
main "$@"
