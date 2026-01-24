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

### 📱 iOS Client

- **语言**：Swift 6.2  
- **最低系统**：iOS 26  
- **开发环境**：Xcode 26  

**核心实现：**

- **SwiftUI**
  - 使用 Observation 框架实现状态驱动 UI
  - 单一数据源（SSOT）设计，确保界面与逻辑一致

- **地图与定位**
  - MapKit + CoreLocation
  - 适配国内环境的坐标纠偏处理

- **架构设计**
  - MVVM + Domain 分层
  - 基于状态机管理游戏阶段（Lobby / Playing / Finished）

---

### ☁️ Backend（Supabase）

后端采用 Supabase，核心思路为：  
**Database as Referee（数据库即裁判）**

客户端只负责展示与交互，关键规则由服务器统一裁决。

#### 🔐 Auth

- Magic Link（邮箱免密登录）
- 登录与注册流程合并，降低使用门槛

#### 🔄 Realtime

- **Broadcast**
  - 用于高频位置同步
  - 提升追逐过程的流畅度

- **Presence**
  - 在线状态维护
  - 支持掉线检测与重连

#### ⚖️ 逻辑裁决（Postgres RPC）

- 关键行为通过数据库 RPC 执行：
  - `attempt_tag`（抓捕判定）
  - `use_item`（道具使用）
- 所有判定在事务中完成，保证数据一致性

- 使用 **PostGIS**
  - 服务器端距离计算
  - 范围扫描与判定

---

## 📂 文档说明

项目相关设计文档位于 `docs/` 目录，包括：

- **产品设计文档**
  - 设计背景
  - 核心玩法
  - 使用流程

- **客户端设计说明**
  - 架构分层
  - 状态管理
  - 代码组织方式

- **后端设计**
  - 数据库结构
  - 状态模型
  - RPC 接口说明

---
