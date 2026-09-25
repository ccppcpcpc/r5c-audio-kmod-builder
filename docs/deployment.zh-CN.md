# NanoPi R5C USB 音频与 AirPlay 2 部署记录

## 1. 最终结果

- 设备：FriendlyElec NanoPi R5C
- 系统：定制 OpenWrt `R24.2.2`，源码修订 `r6535-7727540c1`
- 内核：Linux `6.1.84`，AArch64
- USB 音箱：小米智能音箱 Pro-9835，USB ID `2717:d002`
- AirPlay 名称：`R5C Xiaomi Speaker`
- Shairport Sync：`4.3.2-AirPlay2-smi10-libdaemon-OpenSSL-Avahi-ALSA-pipe-soxr-metadata-mqtt`
- NQPTP：`1.2.4`，共享内存接口 `smi10`

已完成实际验证：

1. USB 音频模块成功加载，小米音箱被 ALSA 识别为 `card 0: Pro9835`。
2. 本地测试音可以正常播放。
3. iPhone 可以发现 `R5C Xiaomi Speaker`，AirPlay 播放正常。
4. 驱动、NQPTP 和 Shairport Sync 已设为开机自动启动。
5. R5C 完整重启后，所有组件均从持久化目录自动恢复；测试用的 `/tmp` 目录已不存在。
6. 重启后 TCP `7000`、UDP `319/320` 均正常监听，内核 `tainted` 值为 `0`。

## 2. 问题原因

原固件缺少 `snd-usb-audio` 及其依赖模块。固件的软件源指向另一套 5.15 内核软件包，因此不能直接通过 `opkg` 安装内核模块。

本次使用固件对应的 LEDE 源码修订编译 Linux 6.1.84 音频模块，并在实际机器上逐个加载验证。模块来自相近配置构建，不是卖家原始编译产物，因此必须与当前 `6.1.84` 固件一起使用。

Shairport Sync 的 AirPlay 2 构建还要求：

- NQPTP 和 Shairport Sync 使用相同的 `smi10` 接口；
- FFmpeg 提供支持浮点平面格式 `fltp` 的 AAC 解码器；
- Avahi 发布 mDNS 服务；
- ALSA 提供音频输出。

精简 FFmpeg 无法通过 AAC 能力检查，因此最终使用隔离的完整 FFmpeg 库。所有专用库都放在 `/opt/shairport-ap2`，没有覆盖系统现有库。

## 3. 持久化文件

### 音频驱动

- 模块目录：`/opt/r5c-audio/modules/`
- 启动脚本：`/etc/init.d/r5c-usb-audio`
- 启动顺序：`S18r5c-usb-audio`

启动脚本按以下顺序加载模块：

```text
soundcore
snd
snd_timer
snd_pcm
snd_hwdep
snd_seq_device
snd_rawmidi
mc
snd_usbmidi_lib
snd_usb_audio
```

脚本会检查 `uname -r` 必须为 `6.1.84`。如果以后升级了固件或内核，它会拒绝加载这些旧模块。

### AirPlay 2

- 程序与专用库：`/opt/shairport-ap2/`
- 配置：`/opt/shairport-ap2/etc/shairport-sync.conf`
- NQPTP 包装脚本：`/opt/shairport-ap2/bin/nqptp-run`
- Shairport Sync 包装脚本：`/opt/shairport-ap2/bin/shairport-sync-run`
- NQPTP 服务：`/etc/init.d/nqptp-ap2`
- Shairport Sync 服务：`/etc/init.d/shairport-ap2`
- 启动顺序：`S97nqptp-ap2`、`S98shairport-ap2`

Shairport Sync 使用：

```text
输出设备：plughw:Pro9835,0
混音设备：hw:Pro9835
音量控制：Playback Volume
输出格式：S16_LE，双声道
```

`plughw` 会把 Shairport Sync 的采样率自动转换为音箱支持的 48 kHz。

## 4. 常用检查命令

检查声卡：

```sh
aplay -l
cat /proc/asound/cards
```

检查内核模块：

```sh
lsmod | grep -E '^(snd|soundcore|mc)'
cat /proc/sys/kernel/tainted
```

检查 AirPlay 进程和端口：

```sh
ps w | grep -E '[n]qptp|[s]hairport-sync'
netstat -lntup | grep -E ':(319|320|7000) '
```

检查日志：

```sh
logread | grep -E 'r5c-usb-audio|shairport|nqptp' | tail -n 100
```

重新启动 AirPlay 服务：

```sh
/etc/init.d/shairport-ap2 restart
/etc/init.d/nqptp-ap2 restart
```

修改显示名称后重启服务：

```sh
vi /opt/shairport-ap2/etc/shairport-sync.conf
/etc/init.d/shairport-ap2 restart
```

## 5. 当前配置

```conf
general = {
  name = "R5C Xiaomi Speaker";
  service_type = "airplay2";
  output_backend = "alsa";
  mdns_backend = "avahi";
  interpolation = "soxr";
};
alsa = {
  output_device = "plughw:Pro9835,0";
  mixer_control_name = "Playback Volume";
  mixer_device = "hw:Pro9835";
  output_format = "S16_LE";
  output_channels = 2;
};
diagnostics = {
  log_output_to = "stderr";
  log_verbosity = 1;
};
```

## 6. 固件升级注意事项

不要把当前 `.ko` 文件用于其他内核版本。即使另一个固件也显示 Linux 6.1.84，其内核配置、补丁或符号布局仍可能不同。

升级固件前应备份：

```sh
/opt/r5c-audio
/opt/shairport-ap2
/etc/init.d/r5c-usb-audio
/etc/init.d/nqptp-ap2
/etc/init.d/shairport-ap2
```

升级后先重新编译与新内核匹配的音频模块，再启用自动加载。Shairport Sync 用户空间程序通常可以继续使用，但仍应重新检查动态库和播放。

## 7. 停用与回滚

先停止并禁用 AirPlay：

```sh
/etc/init.d/shairport-ap2 stop
/etc/init.d/nqptp-ap2 stop
/etc/init.d/shairport-ap2 disable
/etc/init.d/nqptp-ap2 disable
/etc/init.d/r5c-usb-audio disable
```

音频模块已经加载时不要强行卸载。禁用后重启，确认系统正常，再删除对应目录和启动脚本：

```sh
rm -rf /opt/r5c-audio /opt/shairport-ap2
rm -f /etc/init.d/r5c-usb-audio /etc/init.d/nqptp-ap2 /etc/init.d/shairport-ap2
```

## 8. 本地备份

音频模块归档：`r5c-audio-kmods-6.1.84-close-match.tar.gz`

SHA-256：

```text
c12ab179835fbf85dd6520414b5dc98d7555ea9664d7adc40aac6284d0be6f67
```

相关项目与说明：

- OpenWrt USB Audio：<https://openwrt.org/docs/guide-user/hardware/audio/usb.audio>
- Shairport Sync：<https://github.com/mikebrady/shairport-sync>
- NQPTP：<https://github.com/mikebrady/nqptp>
- OpenWrt packages：<https://github.com/openwrt/packages>
