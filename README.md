# NanoPi R5C / OpenWrt 6.1.84 USB 音频与 AirPlay 2

这是一次已经在真实设备上完成播放和重启验证的修复记录，目标是让卖家定制固件中的 NanoPi R5C 驱动 USB 音箱，并作为 AirPlay 2 接收器使用。

> This repository documents a tested USB Audio and AirPlay 2 setup for one specific NanoPi R5C vendor image. Read the compatibility warning before loading the kernel modules.

## 已验证环境

| 项目 | 值 |
| --- | --- |
| 设备 | FriendlyElec NanoPi R5C |
| 固件 | OpenWrt R24.2.2 / `r6535-7727540c1` |
| 内核 | Linux `6.1.84` / AArch64 |
| 内核包 | `6.1.84-1-d7386d74a3619969897951aecec30700` |
| 源码基线 | `coolsnowwolf/lede@7727540c1c9193302b9cfc61212b0cfb09a965b5` |
| USB 音箱 | 小米智能音箱 Pro-9835，`2717:d002` |
| AirPlay 名称 | `R5C Xiaomi Speaker` |

验证结果：

- 10 个 ALSA / USB Audio 模块加载成功；
- `aplay -l` 能识别 `Pro9835`；
- 本地测试音播放正常；
- iPhone 能发现 AirPlay 2 接收器并正常播放；
- 驱动、NQPTP、Shairport Sync 在完整重启后自动恢复；
- 重启后 TCP 7000、UDP 319/320 正常监听；
- 内核 `tainted` 值保持为 `0`。

完整部署与维护记录见 [docs/deployment.zh-CN.md](docs/deployment.zh-CN.md)。

## 兼容性警告

卖家没有提供原始内核 `.config`。虽然模块使用对应源码修订和 Linux 6.1.84 构建，并在上述设备上经过实际验证，但 OpenWrt 配置哈希 `7975362e9ff0d43d2376d7161476d413` 与卖家内核包哈希 `d7386d74a3619969897951aecec30700` 不同。

因此：

1. 这些模块只面向上表所列固件；
2. 先在 `/tmp` 中分阶段测试，不要直接设置开机加载；
3. 不要使用 `insmod -f`；
4. 不要把模块用于其他内核版本；
5. 更换固件后必须重新构建和验证。

## 最短使用流程

从 Releases 下载完整套件 `r5c-audio-airplay2-kit-v1.0.0.tar.gz`，上传到 R5C 的 `/tmp`，然后：

```sh
cd /tmp
tar -xzf r5c-audio-airplay2-kit-v1.0.0.tar.gz
cd r5c-audio-airplay2-kit-v1.0.0
chmod +x test-r5c-audio.sh

./test-r5c-audio.sh check
./test-r5c-audio.sh core
./test-r5c-audio.sh support
./test-r5c-audio.sh usb
```

最后一条命令成功时应显示：

```text
card 0: Pro9835 [智能音箱 Pro-9835], device 0: USB Audio [USB Audio]
```

确认稳定后安装到持久化目录：

```sh
chmod +x install-persistent.sh
./install-persistent.sh .
```

再安装隔离的 Shairport Sync AirPlay 2 环境：

```sh
chmod +x install-airplay2.sh
./install-airplay2.sh
```

安装脚本不会使用当前错误的软件源安装内核包。Shairport Sync 及其专用依赖会从 OpenWrt 官方 24.10 软件包仓库下载，核对实时 `Packages.gz` 中的 SHA-256，然后解压到 `/opt/shairport-ap2`，不会覆盖系统库。

## 仓库内容

- `.github/workflows/build-audio-kmods.yml`：可复现构建工作流；
- `scripts/test-r5c-audio.sh`：分阶段临时加载；
- `scripts/install-persistent.sh`：持久化音频模块；
- `scripts/install-airplay2.sh`：安装隔离的 AirPlay 2 用户空间；
- `scripts/status.sh`：检查声卡、服务和端口；
- `docs/deployment.zh-CN.md`：完整部署、维护和回滚记录；
- `test-on-openwrt.sh`：兼容早期 Actions 产物的一键临时测试入口。

## 构建

工作流固定使用：

- `coolsnowwolf/lede`；
- 提交 `7727540c1c9193302b9cfc61212b0cfb09a965b5`；
- `rockchip/armv8`；
- `friendlyarm_nanopi-r5c`；
- Linux 6.1.84；
- `kmod-media-core`、`kmod-sound-core`、`kmod-usb-audio`。

手动触发 **Build R5C Linux 6.1.84 audio kmods** 后，Actions 会上传未在实机验证的新构建产物。Releases 中标注为 tested 的包才是本次在实机上验证过的文件。

## AirPlay 2 组件

- [Shairport Sync](https://github.com/mikebrady/shairport-sync) `4.3.2`，OpenSSL / Avahi / ALSA / soxr / AirPlay 2；
- [NQPTP](https://github.com/mikebrady/nqptp) `1.2.4`，共享内存接口 `smi10`；
- OpenWrt 官方 `libffmpeg-full`，提供 AirPlay 2 所需的 AAC `fltp` 解码能力；
- ALSA `plughw:Pro9835,0`，自动转换到音箱固定的 48 kHz 采样率。

## 相关资料

- [OpenWrt USB audio support](https://openwrt.org/docs/guide-user/hardware/audio/usb.audio)
- [OpenWrt packages](https://github.com/openwrt/packages)
- [Shairport Sync BUILD.md](https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md)
- [NQPTP README](https://github.com/mikebrady/nqptp/blob/main/README.md)
