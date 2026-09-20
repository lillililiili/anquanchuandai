# 登录背景 V2

使用内置 imagegen 生成新图，原图保留，未使用 CLI。通过 Pillow 仅转码压缩为 WebP（quality 88），未拼接或拉伸画面。

资产：`src/admin-mock/assets/visual/login-showroom-v2.webp`（1536×1024）。替换旧竖版图的 contain 适配：横向连续展厅背景，文字由 HTML 展示，背景 center bottom / cover。产品为概念装备，不代表厂家实物。登录逻辑不变。

## 验证

- 开发页在 1440×900、1920×869 下人工截图检查：三件装备完整、无旧版竖向拼接边界，标题和表单可读。
- 237 项管理端测试通过；lint:admin-mock 通过。
- 未改动认证逻辑、后台接口或数据库。

## 最终生成提示词

```text
Use case: product-mockup. Create a new premium industrial wearable equipment website LOGIN BACKGROUND ASSET, NOT a screenshot or UI mockup. Landscape 1536x1024 aspect ratio 3:2. Continuous pale ice-blue and white futuristic electrical-industry showroom filling the entire image, seamless atmosphere with no split panels, no vertical boundary or separate solid block. Upper 45 percent is quiet softly lit pale blue architecture/air with very low contrast, reserved for HTML logo and dark title at top left. In the lower half arrange three beautifully detailed complete concept products: a white smart safety helmet on the left, an orange-and-black full-body industrial fall-arrest safety harness upright in the center, and a dark rugged smart wristwatch on the right. All three fully visible including bottom edges, standing on low subtly luminous cyan circular plinths. Keep entire product group strictly inside x=22%-78%, y=46%-82% of frame, with generous extra space below and on both sides for responsive cover crops. Harness top must not enter upper text area. Camera moderately wide, product group medium scale, realistic polished product photography / high quality architectural 3D render. Distant subtly blurred electrical substation beyond glass, soft sky lighting, refined cyan details, continuous reflective pale floor. No words, letters, digits, logos, watermarks, UI controls, icons, branding, people. No oversized objects, no edge-cropped equipment, no portrait composition. Assets are conceptual not specific manufacturer models.
```
