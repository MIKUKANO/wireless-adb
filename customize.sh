SKIPUNZIP=0
. "$MODPATH/scripts/common.sh"
init_data || abort '无法安全创建配置目录'
load_config || abort '配置格式无效；请先备份 /data/adb/wadb_config 后修正'
save_config || abort '配置保存失败'
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/scripts/control.sh" 0 0 0755
set_perm "$MODPATH/scripts/common.sh" 0 0 0644
# WebUI ownership and SELinux context are managed by the module manager.
ui_print '- 中文管理页、安全校验、通知入口已安装；无后台自检'
ui_print '- 新安装默认关闭；请在模块 WebUI 中启用'
ui_print '- 通知栏入口适配支持 ksu://webui 的管理器'
