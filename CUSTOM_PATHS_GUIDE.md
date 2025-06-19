# 📁 AWACS Custom Paths Guide | دليل المسارات المخصصة لأواكس

## 🎯 **Overview | النظرة العامة**

AWACS now supports custom file and directory paths for maximum flexibility while maintaining the default "beside script" behavior for simplicity.

يدعم أواكس الآن مسارات ملفات ومجلدات مخصصة لأقصى مرونة مع الاحتفاظ بالسلوك الافتراضي "جانب السكريبت" للبساطة.

---

## ⚙️ **Configuration Variables | متغيرات التكوين**

Edit these variables at the top of `awacs.sh` (around lines 81-95):

عدّل هذه المتغيرات في أعلى `awacs.sh` (حوالي الأسطر 81-95):

```bash
# ========================================
# CUSTOM PATHS CONFIGURATION | تكوين المسارات المخصصة
# ========================================

CUSTOM_WORK_DIR=""               # Custom work directory | مجلد العمل المخصص
CUSTOM_LOG_DIR=""                # Custom log directory | مجلد السجلات المخصص  
CUSTOM_TEMP_DIR=""               # Custom temp directory | مجلد الملفات المؤقتة المخصص
CUSTOM_CONFIG_DIR=""             # Custom config directory | مجلد التكوين المخصص
```

---

## 🚀 **Usage Examples | أمثلة الاستخدام**

### 🔹 **Default Behavior (Recommended) | السلوك الافتراضي (مستحسن)**

Leave all variables empty for automatic setup beside the script:

اترك جميع المتغيرات فارغة للإعداد التلقائي جانب السكريبت:

```bash
DEFAULT_DIR_NAME="awacs"         # Default folder name | اسم المجلد الافتراضي
CUSTOM_WORK_DIR=""               # Will use: /path/to/script/awacs
CUSTOM_LOG_DIR=""                # Will use: /path/to/script/awacs/logs
CUSTOM_TEMP_DIR=""               # Will use: /path/to/script/awacs/temp
CUSTOM_CONFIG_DIR=""             # Will use: /path/to/script/awacs/config
```

**Result | النتيجة:**
```
📁 script_directory/
├── 🚀 awacs.sh
└── 📁 awacs/                   # ← All files here (configurable name)
    ├── 📁 logs/
    ├── 📁 temp/
    └── 📁 config/
```

### 🔹 **Custom Folder Name | اسم مجلد مخصص**

Change the default folder name easily:

غيّر اسم المجلد الافتراضي بسهولة:

```bash
DEFAULT_DIR_NAME="my-wifi-manager"    # Creates: script_dir/my-wifi-manager/
DEFAULT_DIR_NAME="wifi-awacs"         # Creates: script_dir/wifi-awacs/
DEFAULT_DIR_NAME="network-controller" # Creates: script_dir/network-controller/
```

### 🔹 **System-Wide Installation | التثبيت على مستوى النظام**

For system-wide deployment with standard Linux paths:

للنشر على مستوى النظام مع مسارات لينكس القياسية:

```bash
CUSTOM_WORK_DIR="/var/lib/awacs"
CUSTOM_LOG_DIR="/var/log/awacs"
CUSTOM_TEMP_DIR="/tmp/awacs"
CUSTOM_CONFIG_DIR="/etc/awacs"
```

**Result | النتيجة:**
```
📁 /var/lib/awacs/              # ← Work directory
📁 /var/log/awacs/              # ← Log files
📁 /tmp/awacs/                  # ← Temporary files
📁 /etc/awacs/                  # ← Configuration files
```

### 🔹 **User Home Directory | مجلد المنزل**

For user-specific installation:

للتثبيت الخاص بالمستخدم:

```bash
CUSTOM_WORK_DIR="$HOME/.awacs"
CUSTOM_LOG_DIR="$HOME/.awacs/logs"
CUSTOM_TEMP_DIR="/tmp/awacs-$USER"
CUSTOM_CONFIG_DIR="$HOME/.config/awacs"
```

**Result | النتيجة:**
```
📁 ~/.awacs/                    # ← Work directory
📁 ~/.awacs/logs/               # ← Log files
📁 /tmp/awacs-username/         # ← Temporary files
📁 ~/.config/awacs/             # ← Configuration files
```

### 🔹 **External Storage | التخزين الخارجي**

For external drive or NAS storage:

للقرص الخارجي أو تخزين NAS:

```bash
CUSTOM_WORK_DIR="/mnt/storage/awacs"
CUSTOM_LOG_DIR="/mnt/storage/awacs/logs"
CUSTOM_TEMP_DIR="/tmp/awacs"
CUSTOM_CONFIG_DIR="/mnt/storage/awacs/config"
```

### 🔹 **Mixed Configuration | التكوين المختلط**

You can mix custom and default paths:

يمكنك خلط المسارات المخصصة والافتراضية:

```bash
CUSTOM_WORK_DIR=""               # Default: beside script
CUSTOM_LOG_DIR="/var/log/awacs"  # Custom: system logs
CUSTOM_TEMP_DIR=""               # Default: work_dir/temp
CUSTOM_CONFIG_DIR=""             # Default: work_dir/config
```

---

## 🛡️ **Validation & Safety | التحقق والأمان**

### ✅ **Automatic Validation | التحقق التلقائي**

AWACS automatically validates all paths:

يتحقق أواكس تلقائياً من جميع المسارات:

- ✅ **Path existence** | وجود المسار
- ✅ **Write permissions** | صلاحيات الكتابة
- ✅ **Directory creation** | إنشاء المجلدات
- ✅ **Parent directory access** | الوصول للمجلد الأب

### 🔄 **Automatic Fallback | العودة التلقائية**

If any custom path fails, AWACS falls back to default paths beside the script:

إذا فشل أي مسار مخصص، يعود أواكس للمسارات الافتراضية جانب السكريبت:

```bash
❌ Path setup errors | أخطاء في إعداد المسارات:
   • Cannot create directory: /invalid/path
   • No write permission for directory: /readonly/path

💡 Falling back to default paths beside script
💡 العودة للمسارات الافتراضية جانب السكريبت
```

---

## 🎮 **Interactive Setup | الإعداد التفاعلي**

When using custom paths, AWACS shows informative messages:

عند استخدام مسارات مخصصة، يعرض أواكس رسائل إعلامية:

```bash
ℹ️  Using custom work directory: /var/lib/awacs
ℹ️  استخدام مجلد عمل مخصص: /var/lib/awacs

ℹ️  Using custom log directory: /var/log/awacs  
ℹ️  استخدام مجلد سجلات مخصص: /var/log/awacs
```

---

## 🚨 **Important Notes | ملاحظات مهمة**

### ⚠️ **Permissions | الصلاحيات**

Ensure the user running AWACS has appropriate permissions:

تأكد أن المستخدم الذي يشغل أواكس لديه الصلاحيات المناسبة:

```bash
# For system paths, you may need sudo
sudo ./awacs.sh

# For user paths, normal user is fine  
./awacs.sh
```

### 📝 **Path Requirements | متطلبات المسار**

- Use **absolute paths** | استخدم **مسارات مطلقة**
- Ensure **write access** | تأكد من **صلاحية الكتابة**
- Avoid **sensitive system directories** | تجنب **مجلدات النظام الحساسة**

### 🔄 **Migration | الهجرة**

To migrate from default to custom paths:

للهجرة من المسارات الافتراضية للمخصصة:

1. **Stop AWACS** | أوقف أواكس
2. **Edit configuration** | عدّل التكوين
3. **Copy existing files** | انسخ الملفات الموجودة
4. **Restart AWACS** | أعد تشغيل أواكس

```bash
# Stop AWACS
sudo pkill -f awacs.sh

# Copy files to new location
sudo cp -r ./test/* /var/lib/awacs/

# Update configuration and restart
sudo ./awacs.sh
```

---

## 🎯 **Best Practices | أفضل الممارسات**

### 🏠 **For Home Users | للمستخدمين المنزليين**
```bash
# Keep it simple - use defaults
CUSTOM_WORK_DIR=""               # Recommended
```

### 🏢 **For Enterprise | للمؤسسات**
```bash
# Use standard system paths
CUSTOM_WORK_DIR="/var/lib/awacs"
CUSTOM_LOG_DIR="/var/log/awacs"
CUSTOM_CONFIG_DIR="/etc/awacs"
```

### 🔬 **For Development | للتطوير**
```bash
# Separate dev environment
CUSTOM_WORK_DIR="/tmp/awacs-dev"
CUSTOM_LOG_DIR="/tmp/awacs-dev/logs"
```

### 🚐 **For Portable Use | للاستخدام المحمول**
```bash
# Keep everything with script
CUSTOM_WORK_DIR=""               # Default behavior
```

---

## 🆘 **Troubleshooting | استكشاف الأخطاء**

### Problem: Path creation fails | المشكلة: فشل إنشاء المسار
```bash
Solution: Check parent directory permissions
الحل: تحقق من صلاحيات المجلد الأب

# Fix permissions
sudo chmod 755 /path/to/parent
```

### Problem: Permission denied | المشكلة: رفض الصلاحية
```bash
Solution: Run with appropriate privileges
الحل: شغّل بالصلاحيات المناسبة

# For system paths
sudo ./awacs.sh

# Or change ownership
sudo chown -R $USER:$USER /custom/path
```

### Problem: Custom paths ignored | المشكلة: تجاهل المسارات المخصصة
```bash
Solution: Check variable syntax
الحل: تحقق من صيغة المتغير

# Correct syntax
CUSTOM_WORK_DIR="/full/absolute/path"

# Wrong syntax
CUSTOM_WORK_DIR=~/relative/path    # ❌ Don't use ~
```

---

<div align="center">

## 🎉 **Ready to Customize!** | **جاهز للتخصيص!**

The power is in your hands! Choose the setup that works best for your environment.

القوة في يديك! اختر الإعداد الذي يناسب بيئتك أكثر.

**🛡️ AWACS: Your WiFi, Your Way 🛡️**  
**🛡️ أواكس: واي فايك، على طريقتك 🛡️**

</div>