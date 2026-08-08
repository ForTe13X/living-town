# 146 · 视觉大改 · reference 素材集（车道 V · item①）

> 用户 2026-08-07：town map polish / total overhaul（terrain、building skin/appearances，类星露谷），工作流=实机图片 reference + chrome session GPT img-gen 出草图/原型 → reference 素材集 + 丰富 building 种类。**R4 已 waive**（生成图可当出货资产/入 git）——但实务上生成图作**风格锚 + game sprite 底稿**，出货像素仍须适配游戏分辨率/俯视网格。

## 素材集（`docs/media/references/`）

| # | 文件 | 内容 | 来源 | 用途 |
|---|---|---|---|---|
| 1 | `ref_buildings_v1_stardew.png` | 11 栋建筑外观参考表（星露谷风、暖色、统一像素）：BAKERY CAFÉ / BLACKSMITH / GENERAL STORE / LIBRARY / BATHHOUSE / COTTAGE / **TRAIN STATION / HARBOR DOCK / WAREHOUSE / WATERMILL / MARKET STALLS** | GPT img-gen（chrome session, 2026-08-07） | building 外观风格锚 + 新经济建筑(车站/码头/仓库/磨坊/集市)的造型底稿 |

> ⚠️**2026-08-08 订正**：首次提交时**存错了文件**——`download` 点击开的是全屏预览而非下载，我按时间戳抓了 Downloads 里另一项目(Jianghu)的角色图，导致 ref_buildings/ref_terrain 一度是**武侠角色图不是本镇素材**（AT1 实读抓到）。已用**页内 JS `fetch(img.src)→blob→a.download`** 取回真图替换 buildings（真 11 栋表已核）。**terrain 暂缺**：Chrome 拦第二个自动下载 + reload 后图未渲染，terrain 真图（7 类地砖，2.7MB，已在 ChatGPT 会话里）**待重取**（下一轮单独一次下载即可）。⇒ 表里 terrain 行**先撤**，待重取后补。

**建筑种类对齐**：现有 8 栋（cafe/home/home2/shop/work/wash/library + test）→ 参考表覆盖其身份 + **补齐车道 E 需要的 5 类新经济建筑**（车站/码头/仓库/水磨坊/集市），一举衔接视觉与经济车道。

## 待生成（collection 续充，下一轮 img-gen）
- **terrain tileset**：草地/土路/石铺/水岸/农田 的星露谷风地砖（衔接 AP1/AP2 已做的石街/广场）。
- **building 变体**：同类多外观（多户民居不同屋顶/门色）、季节皮。
- **经济建筑细节图**：车站/码头/仓库的近景 + 内部（衔接室内身份 AM 系）。
- **props/装饰**：路灯/招牌/货箱/农具（衔接 AP1 的 verge 街具）。

## 落地纪律（reference → 出货）
1. 生成图=**风格/构图锚**，不直接原样塞进游戏（分辨率/俯视网格/调色板要对齐现有 `WorldView.gd` 的 T 格与 palette）。
2. 出货 building 皮走 `WorldView.gd` 的程序化绘制或对齐网格的 sprite——**纯 View、Sim 读不到 ⇒ 零金标**（同 AM/AP 系纪律：改 building 外观不动导航挡格/advertises 即零金标）。
3. **新经济建筑的"外观"(V) 与"机制"(E) 分开**：V 只做样子（零金标）；E 做运输/物资（移金标，docs/144）。两车道 owns 错开、可并行。

## 工作流备注（chrome GPT img-gen）
- 用户 Chrome（"Browser 1"）已连、ChatGPT Pro 已登录。img-gen 走 chatgpt.com、~1 分钟/张、下载到 `~/Downloads` 再 `cp` 进 `docs/media/references/`。
- prompt 模板：俯视/微俯角 + 星露谷风 + 暖色 + 统一像素分辨率 + 中性背景 + 具名建筑清单 + "游戏美术参考"。
