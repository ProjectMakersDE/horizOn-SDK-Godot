# [1.9.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.8.0...v1.9.0) (2026-10-02)


### Bug Fixes

* use public health endpoint for Godot host checks ([d32fc19](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/d32fc194ced39da1c6d35103b85ba36441095e70))


### Features

* **validated-actions:** optional run start context and sus result ([14e5e57](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/14e5e570471ea61a88acdab61b2fae3255adace2))

# [1.8.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.7.3...v1.8.0) (2026-10-01)


### Bug Fixes

* **auth:** let the server issue the anonymous token on signup ([f081038](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/f081038d72156531452c041b06106570e950a1d6))
* **cloud-save:** authenticate saves and POST binary loads ([b4700a3](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/b4700a3b0cb715faa6a2f0647d7cd635073db3ac))
* **gift-codes:** send the player session when redeeming a code ([9403888](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/9403888b5bf8b9f2c15fe0af26cbf971041c7311))
* **http:** clear error when still rate limited after the last retry (TASK-885) ([1cb238e](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/1cb238ed3cf775d6e96b4056f001e654e3e317b0))
* **validated-actions:** keep the run on LEADERBOARD_MISMATCH like the server order of checks ([dcf2fe8](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/dcf2fe88f2683cc41fcd8bded108c046fa9b9dce))
* **validated-actions:** leave requested and credited absent when the server omits them ([4f8ffb7](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/4f8ffb7fc0556eeb4e24f88da90fbbc0a5ac8027))
* **validated-actions:** report NOT_SUPPORTED for a generic 404 and end the run after any 2xx submit ([3cdbd06](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/3cdbd06c8b7efe353860b1034a48d4cb7ac81213))


### Features

* **player-profile:** add player profile, leaderboard profiles and gift code unlocks ([71a9373](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/71a9373351eb54e9d0be4c6f611bd6feee6000ba))
* **validated-actions:** add server-owned player state with getState and a cached current state ([5dc1dc6](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/5dc1dc6b53f1358bf8b680c253b9f607f6c2755e))
* **validated-actions:** add validated runs with tickets, input log hash and rejection codes ([548d535](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/548d53584fe0835ce7b72e23ebb5cfefc12bbc1b))
* **validated-actions:** upload input log evidence and handle PLAYER_BANNED ([6f99f90](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/6f99f90df4623027b175d9bb7e3685b89f77e8b6))

## [1.7.3](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.7.2...v1.7.3) (2026-09-30)


### Bug Fixes

* **auth:** let the server issue the anonymous token on signup ([a9b32a9](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/a9b32a90842debb2826295b72e3c98b3f9ca3300))

## [1.7.2](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.7.1...v1.7.2) (2026-09-28)


### Bug Fixes

* **ci:** initialize Godot class cache ([731b469](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/731b469fd4c315e2e53faccee5ec99197377727c))
* **ci:** run transport tests on develop ([a4e43fb](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/a4e43fbd70cef201ea5271dd6f369902d34ffb12))
* **ci:** wait for the mock server before the transport test ([5b8695e](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/5b8695e70457818f80b7a58a41f7ae39b84f7d26))
* **http:** add deleteAsync and send the real HTTP method on the wire ([fb00443](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/fb0044345462710e23b97c53d28caa7c59e5e3ae))
* **security:** test signed leaderboard transport ([30b7b31](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/30b7b31c68a4fd033c35ab9f2993374e35d863cf))

## [1.7.1](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.7.0...v1.7.1) (2026-09-01)


### Bug Fixes

* **security:** attach sessions to leaderboard submits ([d2f1eb9](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/d2f1eb9fe7e0b3f21cee9287f59b749f59588c71))

# [1.7.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.6.0...v1.7.0) (2026-06-24)


### Features

* **localization:** add localization core module and example ([3b5c92c](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/3b5c92cb744b6508d0f6b45a96f4a06c5ae1351e))

# [1.6.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.5.0...v1.6.0) (2026-06-17)


### Features

* **crash:** add crash reporting to Godot SDK ([36741dc](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/36741dcbaa8c835fd2cb2995f9a3c338e7f78f58))

# [1.5.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.4.1...v1.5.0) (2026-05-22)


### Features

* add multi-board leaderboard helpers ([df4e9ed](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/df4e9ed160f20b6fc71eee9efd242606307ff7c4))

## [1.4.1](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.4.0...v1.4.1) (2026-05-14)


### Bug Fixes

* **sdk:** add per-feature minimal examples and Hello horizOn entry (TASK-217) ([0bc69ad](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/0bc69ad45da581cdcc84bc187c1ca51d2d8c83ee))

# [1.4.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.3.0...v1.4.0) (2026-04-20)


### Features

* **apple-signin:** apple sign-in support in godot sdk ([3cbea20](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/3cbea20413083571e694e200367c407170339179))

# [1.3.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.2.3...v1.3.0) (2026-04-11)


### Features

* **email:** add email sending manager with template and scheduling support ([36822ef](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/36822ef1c5a458e519029cd05f5364cc7e8b31fd))

## [1.2.3](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.2.2...v1.2.3) (2026-03-04)


### Bug Fixes

* pre-validate response body before JSON parsing ([7a0a129](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/7a0a129eaa55343a811f59b747d0da5324c86920))

## [1.2.2](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.2.1...v1.2.2) (2026-03-04)


### Bug Fixes

* **crashes:** ensure appVersion is never empty in crash requests ([508a070](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/508a070167bef5ee768f1674943195d0a462fffb))

## [1.2.1](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.2.0...v1.2.1) (2026-03-04)


### Bug Fixes

* **crash:** correct API endpoint paths and request body format ([fccbb99](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/fccbb991e90908f1f79397423c2c211f786e6eeb))

# [1.2.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.1.0...v1.2.0) (2026-02-20)


### Bug Fixes

* make google_redirect_uri required for Google auth ([44b0a12](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/44b0a1240d9144394dec57b3f12d4d763fc4f9bd))


### Features

* add Google Auth panel to test UI ([bc58f68](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/bc58f68c172f2b0a0e40dbdf48badb714b20c101))
* single-host direct connect and auto-version sync ([5cb128a](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/5cb128a717d85a291d7dcf65b95faa2a23a60044))

# [1.1.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.0.0...v1.1.0) (2026-02-13)


### Features

* add changelog sync trigger to release workflow ([7ac74fe](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/7ac74fef8d63e756b49676a1e7d227aa1b0c85bc))

# 1.0.0 (2025-12-14)


### Features

* add semantic-release CI/CD and project setup ([331914f](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/331914f8d0f26094bb48593183f93d16e8a9594e))
