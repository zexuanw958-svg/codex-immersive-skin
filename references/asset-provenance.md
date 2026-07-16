# 示例素材来源

本仓库的两张示例背景均在本项目内以 SVG 源文件生成，不使用照片、角色、Logo、商标、字体或任何外部图片素材。SVG 通过 macOS 系统工具 `sips` 转换为运行时使用的 PNG。

> **NOTICE 说明：** 仓库保留的 NOTICE 中提到的 “bundled portal demo” 不在本仓库或发布包内；当前随仓库分发的示例背景仅为下述“晨雾”和“暖沙”两套原创抽象渐变背景。

## 晨雾

- 运行时文件：`assets/morning-mist.png`
- 可复现源文件：`references/generated-assets/morning-mist.svg`
- 尺寸：2400 × 1350
- SHA-256：`218d77153475ce7bd433ce82b29650f81529c7e9242a0cb356d81bf44d25dcfe`
- 构成：线性渐变、径向渐变、椭圆与抽象曲线。

## 暖沙

- 运行时文件：`examples/warm-sand/background.png`
- 可复现源文件：`references/generated-assets/warm-sand.svg`
- 尺寸：2400 × 1350
- SHA-256：`970b3d79f3fd7433791f31d8fc2a37a5f7d77650a55527b9235d0684a87cf1a8`
- 构成：线性渐变、径向渐变、圆形与抽象曲线。

## 复现命令

```bash
sips -s format png references/generated-assets/morning-mist.svg \
  --out assets/morning-mist.png
sips -s format png references/generated-assets/warm-sand.svg \
  --out examples/warm-sand/background.png
```

本说明只覆盖仓库自带示例素材。用户自行添加图片时，应确认自己拥有相应权利或授权。
