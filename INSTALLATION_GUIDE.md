# 🚀 AWACS Installation Guide | دليل تثبيت أواكس

## 🎯 **Installation Options | خيارات التثبيت**

### 🔧 **Option 1: Interactive Installation (Recommended) | التثبيت التفاعلي (مستحسن)**

For full customization and control:
للتخصيص الكامل والتحكم:

```bash
# Download the installer | تحميل المثبت
wget https://github.com/hmne/awacs/raw/main/install.sh

# Make it executable | جعله قابل للتنفيذ
chmod +x install.sh

# Run interactively | تشغيل تفاعلي
sudo ./install.sh
```

**Features | الميزات:**
- ✅ **Language selection** | اختيار اللغة
- ✅ **Setup mode choice** | اختيار وضع الإعداد
- ✅ **Full customization** | تخصيص كامل
- ✅ **Advanced options** | خيارات متقدمة

---

### ⚡ **Option 2: Quick Install with Defaults | التثبيت السريع بالافتراضي**

For automated installation with safe defaults:
للتثبيت التلقائي بالإعدادات الآمنة:

```bash
curl -fsSL https://github.com/hmne/awacs/raw/main/install.sh | sudo bash
```

**Default Settings | الإعدادات الافتراضية:**
- 🌍 **Language**: Bilingual (English + Arabic)
- ⚡ **Performance**: Balanced mode (90s recovery)  
- 📝 **Logging**: Local files only
- 🛡️ **Security**: No open network connections
- 🌙 **Night Mode**: Disabled (normal operation)
- 🔧 **Service**: Auto-created and started

---

## 🛡️ **Security & Safety | الأمان والسلامة**

### ✅ **Safe Defaults Applied | إعدادات آمنة مطبقة**

- **No open networks**: Won't connect to unknown public WiFi
- **Known networks only**: Connects only to saved/configured networks  
- **Local logging**: No data sent to external servers
- **User control**: Full control over network connections

### ❌ **What's Disabled by Default | ما هو معطل افتراضياً**

- ❌ Auto-connection to open/public networks
- ❌ Night mode power saving
- ❌ Remote logging to external servers
- ❌ Debug mode and test mode

---

## 🎮 **After Installation | بعد التثبيت**

### 📋 **Basic Commands | الأوامر الأساسية**

```bash
# Check status | فحص الحالة
awacs status

# View help | عرض المساعدة  
awacs --help

# View logs | عرض السجلات
journalctl -u awacs -f

# Restart service | إعادة تشغيل الخدمة
sudo systemctl restart awacs
```

### ⚙️ **Configuration | التكوين**

The script is installed at | السكريبت مثبت في:
```
/opt/awacs/awacs.sh
```

Edit configuration variables at the top of the file to customize behavior.
عدّل متغيرات التكوين في أعلى الملف لتخصيص السلوك.

---

## 🆘 **Troubleshooting | استكشاف الأخطاء**

### ❓ **Interactive installer not working?**

If `curl | sudo bash` doesn't ask questions:

1. Use **Option 1** (download first, then run)
2. Or wait 10 seconds for default installation

### ❓ **Need to reconfigure?**

```bash
# Stop the service | إيقاف الخدمة
sudo systemctl stop awacs

# Edit configuration | تعديل التكوين
sudo nano /opt/awacs/awacs.sh

# Restart | إعادة التشغيل
sudo systemctl start awacs
```

### ❓ **Want different settings?**

Run the installer again - it will overwrite with new settings:
شغّل المثبت مرة أخرى - سيستبدل بالإعدادات الجديدة:

```bash
sudo ./install.sh
```

---

## 🎯 **Support | الدعم**

- **GitHub Issues**: https://github.com/hmne/awacs/issues
- **Created by**: NetStorm - AbuNaif from Kuwait 🇰🇼
- **Documentation**: See README.md

---

**🛡️ AWACS: Always Watching, Always Connected 🛡️**