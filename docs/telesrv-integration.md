# DarkMoon（telesrv）接入方案

本客户端接入自部署的 MTProto 兼容服务端 telesrv（`E:\MyPj\TgSever`，协议扩展在 td fork 的
`_schema/telesrv.tl`）。参照实现：Android（`Telegram-Android` 提交 `69cc9ccf0`、`e3894be5a`、
`9b4ce61f0`）和 Telegram Desktop（`tdesktop` 提交 `18aac3c905`、`2809fa5d95`、`32f2696b62`、
`6ec13169f5` 起的权限系列、`7dd0bfde6f`/`b93c48c0ee`/`c063a78148` 设备绑定）。服务端客户端集成
文档：`TgSever/docs/password-login.md`、`code-login-switch.md`、`sign-up-switch.md`、
`admin-panel-api.en.md`（`set-permissions`、`set-device-limit`）、`apns-push.md`。

## 已定的决策

- 服务器：`167.104.102.244:2398`，单后端，规范 DC 为 2；RSA 公钥指纹 `0xf5046c55aea0a065`
  （2026-11-08 从 `167.104.103.22` / `0x5d729d647fa6567c` 换过来）。
- bundle id `cc.darkmoon`；`api_id`/`api_hash` 保持默认（服务端不校验）；Team ID 和描述文件
  最后再定，开发期用模拟器构建（`build-system/fake-codesigning` + `--disableProvisioningProfiles`）。
- 链接：`darkmoon.cc` 替代 `t.me`，scheme `dm://` 替代 `tg://`；`t.me` 不再当内部链接。
- 登录参照 Android 的流程，界面用 iOS 原生风格；另做已登录后的登录密码管理（Android 没有）。
- 设备绑定要做；员工权限全部入口都要拦，**发送白名单连联系人选择器也过滤**。
- 新文案全部本地化：键加在 `en.lproj/Localizable.strings`（`Telesrv.` 前缀），其他语言由服务端
  `ios` 语言包覆盖。

## 阶段

| 阶段 | 内容 | 状态 |
|---|---|---|
| 0 | 产品身份：`build-system/darkmoon-configuration.json`（`team_id` 仍是占位值）；`Telegram/BUILD` 给 `cc.darkmoon` 输出 `darkmoon.cc` 的 Universal Links 和 communication notifications | 已提交 `673e1f6c8f`、`c98b0a8ecb` |
| 1 | 连接：`TelesrvServer.swift`；DC 1–5 种子同一地址；初始 DC 统一为 2；RSA 公钥；去掉 DoH/CloudKit 备用地址发现；未登录只预取当前 DC 的 key | 已提交 `673e1f6c8f` |
| 2 | 链接：`TelesrvLinks.swift`（`telesrvLinkHost`、`telesrvUrlScheme`）；解析只认 `darkmoon.cc`；入口处 `dm://`→`tg://`；所有生成的链接用常量；只注册 `dm` scheme | 已提交 `c98b0a8ecb` |
| 3 | TL 和登录：`telesrv.tl` 由 genrule 拼进 schema；`Telesrv/TelesrvLoginConfiguration.swift`、`TelesrvLoginPassword.swift`；状态 9/10；AuthorizationUI；隐私与安全的“登录密码” | 已提交 `73a2660899` |
| 4 | 设备绑定：`BuildConfig.m` 的 `device_id`；登录、两步验证、注册、扫码批准的设备错误提示 | 已提交 `a300e06c71` |
| 5 | 员工权限：`Telesrv/TelesrvPermissions.swift`、`AccountContext/TelesrvPermissionsContext.swift`；TelegramCore 底层拦截删除/清空/删聊天；403 全局提示和刷新；各界面入口 | 已提交 `ffdb9a4fe9`、`a5bcdc70a8` |
| 6 | 本地化：新增键见下文“文案键” | 随各阶段 |

整个分支只在 Windows 上写成，**一次都没有编译过**，下面的验证全部要在 Mac 上做。

## 编译和签名

不在本地编译：CI 用 WarpBuild（`.github/workflows/ios-darkmoon-warp.yml`，手动触发），产出用自签名占位证书签的
ipa，由持有企业证书的负责人重签（`docs/telesrv-signing.md`）。占位描述文件由 `build-system/Make/PlaceholderCodesigning.py`
在运行器上现场生成，不需要任何签名 Secret。默认不打包扩展（`Make.py build --disableExtensions`），负责人只签
`cc.darkmoon` 一个 bundle。

## 在 Mac 上要验证的

1. `Make.py build --continueOnError`（`--configurationPath build-system/darkmoon-configuration.json`，签名用
   `build-system/fake-codesigning` 加 `--disableProvisioningProfiles`）。`team_id` 占位值能否通过 Make.py 未验证。
2. TL 生成：只有 `flags:#` 的 `telesrv.getMyLoginPassword` 能否正常生成（生成器源码看没问题）。
3. 测试：`Make.py test --target //submodules/TelegramCore:TelegramCoreTests`（`TelesrvLoginTests`、
   `TelesrvPermissionsTests`、`ProxySettingsTests`），`//submodules/UrlWhitelist:UrlWhitelistTests`。
4. 全新模拟器：握手成功、验证码登录、密码登录/注册/两步验证、登录密码设置页、`dm://` 和 `darkmoon.cc` 链接、
   服务端设权限后各入口的表现、设备上限时的提示。推送需要真机和证书。

## 员工权限覆盖范围

- **发送**：聊天输入框换成受限面板并说明原因；`ChatController.sendMessages` 最后拦截；权限变化时聊天重新布局；
  聊天列表/搜索/分享面板/新版分享页/社区/相册的选择器把受限聊天置灰；Story 回复拦截。Siri 和通知快捷回复靠服务端拒绝。
- **白名单**：同上，另外通讯录列表和联系人搜索把名单外的用户置灰。
- **删除**：消息菜单去掉已发出消息的删除；TelegramCore 的 `deleteMessagesInteractively` 底层拦截。
- **编辑**：`canEditMessage(context:)` 统一拦截已发出的消息。
- **清空记录 / 删除聊天 / 退出**：TelegramCore 底层拦截（先删本地的问题因此不会出现）；聊天列表、聊天页、资料页弹出原因。
- **加入**：频道/群组底部的加入按钮弹出原因；邀请链接、文件夹链接靠服务端拒绝。
- **新建群组/频道、添加联系人**：“新建”页按权限隐藏；资料页和聊天顶栏的添加联系人弹出原因；其他入口靠服务端拒绝。
- 服务端拒绝（`403 TELESRV_PERMISSION_*`）时：全局提示 `Telesrv.Permission.Denied`（2 秒内最多一次），并刷新 app config（30 秒内最多一次）。

## 文案键

新增 43 个，都在 `Telegram/Telegram-iOS/en.lproj/Localizable.strings` 末尾，前缀 `Telesrv.`（登录、注册、登录密码设置、
设备绑定、员工权限）。服务端 `ios` 语言包补上这些键即可，客户端不用再改。另外这 10 个已有键的英文原文把 `t.me`
换成了 `darkmoon.cc`，其他语言的服务端语言包里也要改：`Username.LinkHint`、`Channel.Username.LinkHint`、
`EmptyGroupInfo.Line3`、`PrivacyPhoneNumberSettings.CustomPublicLink`、`Premium.Limits.PublicLinksInfo`、
`Business.Links.SimpleLinkInfoUsernamePhone`、`Business.Links.SimpleLinkInfoUsername`、
`Business.Links.SimpleLinkInfoPhone`、`CocoonInfo.IntergrateInfo`、`SocksProxySetup.QrCode.TMeLink`。

## 不显而易见的点

- **TL 代码是构建时生成的。** 服务端文档建议 iOS 手写 `ApiTelesrv.swift`，在本仓库行不通：
  TelegramApi 由 Bazel 从 schema 生成并由表驱动引擎序列化。telesrv 方法放在独立的
  `submodules/TelegramApi/telesrv.tl`，由 genrule 和 `generate-swiftpm.sh` 拼接，升级 Layer 时
  只替换 `swift_scheme.tl`。
- **删除、清空、退出聊天是先删本地再发请求，并吞掉服务端错误**
  （`ManagedCloudChatRemoveMessagesOperations.swift`），所以权限必须在操作前拦，403 兜底不够。
- **发送白名单**：`send=false` 时除收藏夹外都不能发，白名单不是例外；`send=true` 且白名单开启时
  私聊只能发给名单内用户（私密聊天按对方用户判断），群和频道不受影响。缺键或 `true` 都算允许。
- **登录 SRP challenge 一次性、5 分钟过期、绑定 auth key**，不落盘，每次提交前重新获取；
  `SRP_ID_INVALID`/`SRP_PASSWORD_CHANGED`/`AUTH_KEY_PERM_EMPTY` 自动重试一次。
- **`UnauthorizedAccountState` 的编码值 4 从未使用**，新状态用 9 和 10。
- **unrestricted-voip 能力只有官方能拿到**，`cc.darkmoon` 下每条 VoIP 推送都必须立即上报 CallKit
  来电，服务端不能用 VoIP 推送发其他内容。推送 topic：`cc.darkmoon` 与 `cc.darkmoon.voip`。
- **设备 ID 必须 App 与所有扩展共用**（它们各自发 `initConnection`），所以存在共享 keychain 组，
  不用 `identifierForVendor`。
- 装过官方版的设备换公钥后要删掉应用重装，否则用 keychain 里缓存的旧 auth key。
