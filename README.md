# 🏃💨 RunningMan

基于真实地理位置（LBS）的 iOS 多人实时对抗游戏  
**Real-time Multiplayer LBS Tag Game for iOS**

![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![iOS](https://img.shields.io/badge/iOS-26-blue)
![Xcode](https://img.shields.io/badge/Xcode-26-blue)
![Backend](https://img.shields.io/badge/Backend-Supabase-green)

---

## 📺 Gameplay Demo

▶️ **完整对局演示视频（约 5 分钟）**  

Bilibili:  https://www.bilibili.com/video/BV1Q6zyB3EgK/  
YouTube:  https://youtu.be/3V1tW2nbBYw

> 视频为真机录制。  
> 包含登录、主页、创建房间、对局过程以及游戏结束等完整流程。  
> **这是我完成的第一款完整游戏项目。**

---

## 📖 项目简介

**RunningMan** 是一款基于真实地理位置的 iOS 多人实时对抗游戏，玩家在同一现实区域内进行追逐与博弈。

游戏支持多人在线对局，适合在校园、公园等开放场景中游玩，玩家的移动会直接影响对局进程。对局中，追捕者需要靠近并完成「撕名牌」操作来抓捕对手，而逃脱者则需要利用地形和道具尽量存活。

游戏内提供了隐身、雷达、护盾等道具，用于在追逐过程中制造变数。同时，系统会记录玩家的对局表现，解锁不同的成就，用于展示参与情况和游戏经历。

玩家分为三个阵营：

- **Hunters（追捕者）**
- **Runners（逃脱者）**
- **Observer（观察者）**

追捕者与逃脱者在限定区域内进行对抗，观察者可以全程旁观对局。

---

## 🎮 核心玩法

- **LBS 实景对抗**  
  基于 GPS 的实时位置同步，现实世界即游戏地图。

- **动态安全区（缩圈机制）**  
  类似 Battle Royale 的安全区收缩，防止消极躲藏，迫使玩家持续移动。

- **道具博弈**  
  隐身、雷达、护盾等道具可在对局中使用，用于追捕或逃脱。

- **服务器裁决**  
  抓捕判定、道具使用等关键行为由服务器统一处理，保证对局公平性。

---

## 🛠 技术架构

项目采用 **MVVM + Clean Architecture**，明确区分 UI、业务逻辑与数据层，便于维护与扩展。

<img width="1219" height="590" alt="System Architecture" src="https://github.com/user-attachments/assets/1ff04d3c-208f-428c-89b8-cb5068b469d5" />

### 📱 iOS App

- **UI 框架**：SwiftUI  
- **开发语言**：Swift 6.2  
- **运行系统**：iOS 26（开发版本）  
- **开发环境**：Xcode 26

**核心实现：**

iOS 端基于 SwiftUI 构建，使用 Observation 框架实现状态驱动 UI，并通过单一数据源（SSOT）保证界面状态与业务逻辑的一致性。地图与定位部分使用 MapKit 与 CoreLocation，并针对国内环境进行了坐标纠偏处理。

整体架构采用 MVVM 结合领域分层的设计方式，通过状态机管理游戏在大厅、对局和结算等阶段之间的流转。


---

### ☁️ Backend（Supabase）

后端基于 Supabase 构建，整体采用「Database as Referee（数据库即裁判）」的设计思路。客户端只负责展示与交互，所有会影响对局结果的关键规则均由服务器统一裁决。

用户登录采用邮箱 Magic Link，将注册与登录流程合并以降低使用门槛。实时部分使用 Supabase Realtime，同步玩家在线状态与位置信息，以保证对局过程的流畅性，并支持掉线检测与重连。

抓捕判定与道具使用等关键逻辑通过 Postgres RPC 在数据库事务中完成，并结合 PostGIS 在服务器端进行距离与范围计算，从而避免客户端自行判定带来的不一致问题。

---

## 📂 文档说明

项目相关设计文档已整理并直接上传，主要包括以下内容：

- **产品设计文档**  
  [RunningMan - 产品设计.pdf](https://github.com/user-attachments/files/24842040/RunningMan.-.pdf)  
  包含设计背景、核心玩法与整体使用流程说明。

- **客户端设计说明**  
  [RunningMan - iOS 架构设计.pdf](https://github.com/user-attachments/files/24842037/RunningMan.-.iOS.pdf)  
  说明 iOS 客户端的整体架构分层、状态管理方式以及主要模块的组织思路。

- **后端与数据库设计**  
  [RunningMan - 后端与数据库设计.pdf](https://github.com/user-attachments/files/24842039/RunningMan.-.pdf)  
  包含数据库结构、多层状态模型以及裁判级 RPC 的设计说明。
