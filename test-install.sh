#!/bin/bash
# ===================================================
# AWACS Interactive Installer Test | اختبار مثبت أواكس التفاعلي
# Advanced WiFi Auto Connection System
# ===================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Clear screen
clear

# Show AWACS banner
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
echo ""
echo -e "${PURPLE}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""

# Language selection
echo -e "${WHITE}${BOLD}🌍 Language Selection | اختيار اللغة${NC}"
echo ""
echo -e "${YELLOW}[1]${NC} English"
echo -e "${YELLOW}[2]${NC} العربية"
echo -e "${YELLOW}[3]${NC} Bilingual | ثنائي اللغة (Default)"
echo ""
echo -n -e "${PURPLE}${BOLD}Select option (1-3): ${NC}"
read -r lang_choice

case "$lang_choice" in
    "1") LANGUAGE="en"; echo -e "${GREEN}✓ Selected: English${NC}" ;;
    "2") LANGUAGE="ar"; echo -e "${GREEN}✓ Selected: العربية${NC}" ;;
    *) LANGUAGE="both"; echo -e "${GREEN}✓ Selected: Bilingual${NC}" ;;
esac

sleep 1
clear

# Setup mode selection  
echo -e "${CYAN}${BOLD}"
echo "  █████╗ ██╗    ██╗ █████╗  ██████╗███████╗"
echo "  ██╔══██╗██║    ██║██╔══██╗██╔════╝██╔════╝"
echo "  ███████║██║ █╗ ██║███████║██║     ███████╗"
echo "  ██╔══██║██║███╗██║██╔══██║██║     ╚════██║"
echo "  ██║  ██║╚███╔███╔╝██║  ██║╚██████╗███████║"
echo "  ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝"
echo -e "${NC}"
echo ""

if [[ "$LANGUAGE" == "ar" ]]; then
    echo -e "${WHITE}${BOLD}🛠️ اختيار وضع الإعداد${NC}"
    echo ""
    echo -e "${YELLOW}[1]${NC} إعداد بسيط (مستحسن)"
    echo -e "${YELLOW}[2]${NC} إعداد متقدم (تخصيص كامل)"
    echo ""
    echo -n -e "${PURPLE}${BOLD}اختر الرقم (1-2): ${NC}"
elif [[ "$LANGUAGE" == "en" ]]; then
    echo -e "${WHITE}${BOLD}🛠️ Setup Mode Selection${NC}"
    echo ""
    echo -e "${YELLOW}[1]${NC} Simple Setup (Recommended)"
    echo -e "${YELLOW}[2]${NC} Advanced Setup (Full Customization)"
    echo ""
    echo -n -e "${PURPLE}${BOLD}Select option (1-2): ${NC}"
else
    echo -e "${WHITE}${BOLD}🛠️ Setup Mode Selection | اختيار وضع الإعداد${NC}"
    echo ""
    echo -e "${YELLOW}[1]${NC} Simple Setup | إعداد بسيط (Recommended | مستحسن)"
    echo -e "${YELLOW}[2]${NC} Advanced Setup | إعداد متقدم (Full Customization | تخصيص كامل)"
    echo ""
    echo -n -e "${PURPLE}${BOLD}Select option | اختر الرقم (1-2): ${NC}"
fi

read -r setup_choice

case "$setup_choice" in
    "2") 
        SETUP_MODE="advanced"
        echo -e "${GREEN}✓ Selected: Advanced Setup${NC}"
        ;;
    *) 
        SETUP_MODE="simple"
        echo -e "${GREEN}✓ Selected: Simple Setup${NC}"
        ;;
esac

sleep 1

# Show final configuration
clear
echo -e "${CYAN}${BOLD}"
echo "  █████╗ ██╗    ██╗ █████╗  ██████╗███████╗"
echo "  ██╔══██╗██║    ██║██╔══██╗██╔════╝██╔════╝"
echo "  ███████║██║ █╗ ██║███████║██║     ███████╗"
echo "  ██╔══██║██║███╗██║██╔══██║██║     ╚════██║"
echo "  ██║  ██║╚███╔███╔╝██║  ██║╚██████╗███████║"
echo "  ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝"
echo -e "${NC}"
echo ""

echo -e "${WHITE}${BOLD}📋 Configuration Summary | ملخص التكوين${NC}"
echo ""
echo -e "${CYAN}► Language | اللغة: ${GREEN}$LANGUAGE${NC}"
echo -e "${CYAN}► Setup Mode | وضع الإعداد: ${GREEN}$SETUP_MODE${NC}"
echo ""

if [[ "$SETUP_MODE" == "advanced" ]]; then
    echo -e "${YELLOW}${BOLD}Advanced setup would continue here...${NC}"
    echo -e "${YELLOW}${BOLD}الإعداد المتقدم سيتواصل هنا...${NC}"
else
    echo -e "${GREEN}${BOLD}Simple setup with default settings:${NC}"
    echo -e "${GREEN}${BOLD}إعداد بسيط مع الإعدادات الافتراضية:${NC}"
    echo ""
    echo -e "${WHITE}• Performance: Balanced (90s)${NC}"
    echo -e "${WHITE}• Logging: Local only${NC}"
    echo -e "${WHITE}• Service: Auto-create${NC}"
fi

echo ""
echo -e "${PURPLE}${BOLD}This is just a test - no actual installation performed${NC}"
echo -e "${PURPLE}${BOLD}هذا مجرد اختبار - لم يتم تثبيت فعلي${NC}"