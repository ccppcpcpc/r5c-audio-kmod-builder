# NanoPi R5C / Linux 6.1.84 USB 音频模块

为这台 OpenWrt R24.2.2 设备构建 USB Audio Class 驱动，目标是让 VID:PID 2717:d002 的小米智能音箱用于 AirPlay 播放。

构建固定使用：

- 源码：coolsnowwolf/lede
- 提交：7727540c1c9193302b9cfc61212b0cfb09a965b5
- 目标：rockchip/armv8、friendlyarm_nanopi-r5c
- 内核：Linux 6.1.84
- 模块：kmod-media-core、kmod-sound-core、kmod-usb-audio

## 下载产物

打开 Actions，进入最新的 Build R5C Linux 6.1.84 audio kmods 运行。成功后在页面底部下载 r5c-audio-kmods-6.1.84。

工作流只在所有模块的 vermagic 等于下面这行时上传产物：

~~~text
6.1.84 SMP preempt mod_unload aarch64
~~~

## 在 R5C 上临时测试

把 artifact 中的 audio-kmods-6.1.84-aarch64.tar.gz 和 test-on-openwrt.sh 放到设备 /tmp，然后执行：

~~~sh
cd /tmp
chmod +x test-on-openwrt.sh
./test-on-openwrt.sh ./audio-kmods-6.1.84-aarch64.tar.gz
~~~

脚本只解压到 /tmp/r5c-audio-test 并逐个 insmod，不写入 squashfs，也不安装 IPK。失败时不要加 insmod -f；重启即可卸载临时模块。

出现 READY: USB audio device detected 后执行：

~~~sh
aplay -l
speaker-test -D default -c 2 -t sine
~~~

如果出现 invalid module format 或 Unknown symbol，请保留完整脚本输出、dmesg | tail -n 100 和 cat /proc/version 的结果。
