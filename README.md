# OpenWrt 客户端管理插件 (luci-app-clientmanager)

一个功能完整的 OpenWrt 客户端管理插件，支持设备查看、访问控制、流量统计等功能。

## 功能特性

- **设备概览**: 实时显示所有连接设备，包括在线状态、IP/MAC地址、厂商信息
- **访问控制**: 阻断/解除阻断设备，设置设备网速限制
- **流量统计**: 记录和展示各设备的流量使用情况
- **设置管理**: 配置自动阻断、流量监控、通知等选项

## 目录结构

```
luci-app-clientmanager/
├── Makefile                          # 编译配置文件
├── README.md                         # 本文件
├── luasrc/
│   ├── controller/
│   │   └── clientmanager.lua        # 控制器（路由和逻辑）
│   ├── model/
│   │   └── cbi/
│   │       └── clientmanager/
│   │           └── settings.lua     # 设置页面模型
│   └── view/
│       └── clientmanager/
│           ├── overview.htm         # 设备概览页面
│           ├── control.htm          # 访问控制页面
│           └── statistics.htm       # 流量统计页面
├── root/
│   ├── etc/
│   │   └── config/
│   │       └── clientmanager        # UCI配置文件
│   └── usr/
│       └── libexec/
│           ├── clientmanager-block.sh       # 设备阻断脚本
│           ├── clientmanager-speedlimit.sh  # 限速脚本
│           └── clientmanager-traffic.sh     # 流量统计脚本
└── po/
    └── zh-cn/
        └── clientmanager.po         # 中文翻译文件
```

## 安装方法

### 方法一：编译到固件中

1. 将本插件复制到 OpenWrt SDK 的 `package` 目录：
```bash
cp -r luci-app-clientmanager /path/to/openwrt-sdk/package/
```

2. 在 SDK 中编译：
```bash
cd /path/to/openwrt-sdk
make menuconfig  # 选择 LuCI -> Applications -> luci-app-clientmanager
make package/luci-app-clientmanager/compile V=s
```

3. 安装生成的 IPK 包：
```bash
opkg install bin/packages/*/luci/luci-app-clientmanager_*.ipk
```

### 方法二：手动安装到运行中的 OpenWrt

1. 复制文件到对应目录：
```bash
# 复制 Lua 文件
scp -r luasrc/* root@192.168.1.1:/usr/lib/lua/luci/

# 复制配置文件
scp root/etc/config/clientmanager root@192.168.1.1:/etc/config/

# 复制脚本文件
scp root/usr/libexec/*.sh root@192.168.1.1:/usr/libexec/
ssh root@192.168.1.1 'chmod +x /usr/libexec/clientmanager-*.sh'
```

2. 重启 LuCI：
```bash
/etc/init.d/uhttpd restart
```

## 使用方法

1. 登录 OpenWrt 管理界面 (LuCI)
2. 在顶部菜单找到 **网络** -> **客户端管理**
3. 使用各个功能页面：
   - **设备概览**: 查看所有设备，可直接阻断或限速
   - **访问控制**: 管理已阻断设备和限速设备列表
   - **流量统计**: 查看各设备的流量使用情况
   - **设置**: 配置插件选项

## 技术说明

### 后端技术

- **Lua**: LuCI 框架使用 Lua 语言编写
- **UCI**: 统一配置接口，用于存储配置
- **Shell 脚本**: 系统命令执行（iptables, tc 等）
- **iptables**: 防火墙规则管理
- **tc (Traffic Control)**: 流量限速

### 前端技术

- **LuCI 模板**: HTML 模板引擎
- **JavaScript**: 页面交互和 AJAX 请求
- **XHR**: LuCI 内置的 AJAX 工具

### API 接口

- `GET /admin/network/clientmanager/api/devices` - 获取设备列表
- `POST /admin/network/clientmanager/api/block` - 阻断设备
- `POST /admin/network/clientmanager/api/unblock` - 解除阻断
- `POST /admin/network/clientmanager/api/limit` - 设置限速
- `GET /admin/network/clientmanager/api/traffic` - 获取流量统计

## 开发指南

### 添加新功能

1. **添加新页面**:
   - 在 `luasrc/controller/clientmanager.lua` 添加路由
   - 在 `luasrc/view/clientmanager/` 创建模板文件

2. **添加 API 接口**:
   - 在控制器中添加 entry
   - 实现对应的处理函数

3. **添加配置项**:
   - 在 `root/etc/config/clientmanager` 添加配置
   - 在 `luasrc/model/cbi/clientmanager/settings.lua` 添加界面

### 调试技巧

1. 查看 Lua 错误日志：
```bash
logread | grep luci
tail -f /var/log/messages
```

2. 手动测试脚本：
```bash
# 测试阻断功能
/usr/libexec/clientmanager-block.sh AA:BB:CC:DD:EE:FF block

# 测试限速功能
/usr/libexec/clientmanager-speedlimit.sh AA:BB:CC:DD:EE:FF 1000 500

# 测试流量统计
/usr/libexec/clientmanager-traffic.sh stats
```

3. 检查 iptables 规则：
```bash
iptables -L FORWARD -v -n
iptables -t mangle -L -v -n
```

## 注意事项

1. **权限**: 脚本需要 root 权限运行
2. **兼容性**: 适用于 OpenWrt 19.07+ 和 21.02+
3. **依赖**: 需要安装 `iptables`, `ip6tables`, `kmod-nft-netdev`
4. **性能**: 大量设备时可能影响性能，建议限制扫描频率

## 常见问题

### Q: 设备显示为 "Unknown" 怎么办？
A: 这是正常的，表示无法从 DHCP 租约或反向 DNS 获取主机名。

### Q: 限速不生效？
A: 确保 `tc` 命令可用，并且网络接口正确（默认 br-lan）。

### Q: 阻断后设备还能访问？
A: 检查 iptables 规则是否正确添加：
```bash
iptables -L FORWARD -v -n | grep <MAC地址>
```

## 许可证

Apache License 2.0

## 贡献

欢迎提交 Issue 和 Pull Request！

## 更新日志

### v1.0.0 (2024-01-01)
- 初始版本发布
- 设备查看功能
- 访问控制功能
- 流量统计功能
- 设置管理功能
