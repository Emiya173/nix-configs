{ config, pkgs, ... }:

{
  time.timeZone = "Asia/Shanghai";

  i18n = {
    defaultLocale = "zh_CN.UTF-8";
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "zh_CN.UTF-8/UTF-8"
      "C.UTF-8/UTF-8"
    ];
    # LC_MESSAGES 不再覆盖 -> 跟 defaultLocale = zh_CN.UTF-8,DMS / GTK / Qt 应用就显示中文
    # LC_TIME 保留 en_US 以拿到 "May 9" 这种英文短日期 (个人偏好;想全中文删掉这块即可)
    extraLocaleSettings = {
      LC_TIME = "en_US.UTF-8";
    };
  };

  console.keyMap = "us";
}
