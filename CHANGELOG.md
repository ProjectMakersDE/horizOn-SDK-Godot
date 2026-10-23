# [1.11.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.10.0...v1.11.0) (2026-10-23)


### Bug Fixes

* **achievements:** consume only normalized route response fields ([6826122](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/682612283cc704ab222dae80ed1a37860a37d9ec))
* **auth:** preserve stored identity when anonymous restore fails ([eb8beeb](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/eb8beeb8e028a481f9d07012893d82b96696f17e))
* **chat:** recover abandoned desktop history locks safely ([baa9e81](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/baa9e81c5737e7bf475022a0149a2da6cac3512e))
* derive group sample pages from current authenticated limits ([a34bc22](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/a34bc228203df7fd7cbf9d1c13a5d492e3e9de18))
* distinguish Apple error signal from boolean result ([8063c5b](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/8063c5bf7f6562b81c2d5bff19bd3b6941dae462))
* distinguish NUL in Groups canonical keys and values ([0620437](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/06204371d18c57866df81cb213568b5bd3ec0130))
* **docs:** correct achievement and group reference contracts ([1b6efde](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/1b6efde94636aed6c7f10a0d34445da5c1264097))
* **examples:** protect statistics intent ownership and recovery ([4c61a38](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/4c61a38778650071e9135360c2d30f0c5edae916))
* expose explicit disconnected chat snapshots ([3820d98](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/3820d98f9832146313199428844fdba5361487ff))
* format empty achievement replay arrays safely ([8317784](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/8317784c30b696d1cb3f50523c696e57da5be91f))
* **gift-codes:** match server Unicode blank ID validation ([7644c24](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/7644c24a110d4e0f7b6ef3cb286dfda03667c982))
* **groups:** preserve original JSON data during metadata updates ([be0ff9e](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/be0ff9e1fec380c384fcf225de5ae52323c765b3))
* handle compact achievements and invalidate atomic rewards ([19a4e56](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/19a4e5648a855d12b3ec90d3ed3da7b90ba9a69c))
* honor configured social shared and match limits ([105baf5](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/105baf5496373ed9fb99870cb8e0251ae6f6f642))
* **inbox:** persist only authorized original claim intents ([a308bc4](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/a308bc47217540aa07d380bc339dd65cf24e6790))
* **inbox:** retain legacy group acceptance references ([d44c29a](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/d44c29a1e1ff64a50a3699700860539b66fa645a))
* **items:** accept configured quotas and retained inventories ([#30](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/issues/30)) ([212d72b](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/212d72b3cbf9166f067790955abc6e2e87128168))
* **marketplace:** avoid inherited reference method collision ([00bfa01](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/00bfa01ca456bf782cc95d50594ab0eb39848308))
* **marketplace:** bind receipt revision to original intent ([13066af](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/13066afec198d523af75b4921024585e374b57a0))
* **marketplace:** recover proven dead Godot send owners after process death ([086f076](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/086f0764deb58bbb08365551055e9e72a1fea86b))
* **marketplace:** release send ownership when the Godot screen is destroyed ([8deea48](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/8deea483f93484a7e6b9faa802bc94e33cd7b41e))
* preserve Groups metadata tokens and parse escaped aggregates ([446c88a](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/446c88a4a685721077b151502e8791512cae66ef))
* preserve match watermarks with escaped groups transport regression ([c0d6831](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/c0d6831b7cb025cf1589a7ec6d6e0db01057bdba))
* **readme:** link the horizOn Discord with its real invite code (TASK-1046) ([e314b54](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/e314b54258d0bb5d5c0f4c4b69bc8271ce94f619))
* **realtime:** correlate subscription replies and acknowledge resync (TASK-995) ([7a50597](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/7a505976ec64580bde8f21d2a1ebb10ec7793b95))
* require an eligible email sample recipient and bound OAuth claims ([e35c105](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/e35c105cc1f77a7ca94674e164794ed6d0c8f7e7))
* retain group revision floors throughout the auth context ([49d6fa5](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/49d6fa519b0c64028fa4aa80d8f0bade61929416))
* retain large configured group metadata through all wire checks ([4bf5b9b](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/4bf5b9b7b36484b9e62fc5b0c57275dbbd191116))
* retain ranked source bindings throughout the auth context ([6ec32c0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/6ec32c023060cf70d83e7d0f25c715b1897741df))
* serialize large original match state without quadratic copies ([762e9a0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/762e9a04eb42365ca84e18da4547d5bedf0ceffc))
* **statistics:** expose atomic Godot session batches (TASK-1005) ([4cf1329](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/4cf1329b4a5106ded107b5e6809ee03355b89c12))
* **statistics:** honor server configured catalog limits ([7f2c7c6](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/7f2c7c6e83c76439235aacf0804f78e129ce2fb9))
* tokenize escaped unicode runs without per-character regex backtracking ([1289f58](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/1289f58ca21a13921464fb1c784f0fcfd2569c51))
* **transport:** jitter transient rate-limit retries ([eff01ae](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/eff01ae3ee14ec2ffff152c7dac00ecf924bc3ba))
* use lossless key identity in Groups wire duplicate checks ([f819afd](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/f819afdc959cdbbe278d84408dcb7086afe1f813))


### Features

* **achievements:** add session-safe progression and reward handoff ([fbea93e](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/fbea93eb5fe8748da0f7150fbea040e27fce5bd6))
* add explicit revision-safe friends flows ([39c2378](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/39c2378880fbdbc645b4b4f560c19de682a62cbf))
* add push-driven chat with durable message recovery ([db0a83c](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/db0a83cb71715da555f8e0093bb2b24a8511879d))
* **chat:** persist device history apart from bounded live feeds ([81fe2f0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/81fe2f0cdea726b3ab89538f349e25cd9ef31006))
* **gift-codes:** expose safe value rewards and preserve redemption identity ([c75c1b5](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/c75c1b5545203d33c81fab219896d772ccc65c71))
* **gift-codes:** persist exact V2 redemption intents ([72120fc](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/72120fcd01ddb8f67b637a6d67f27f17e07bf6ed))
* **groups:** add explicit bounded Godot player operations ([590da08](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/590da08b76c567ddd0a0a5aa31e5cdd2cab534a9))
* **inbox:** add session-safe snapshots and atomic reward claims ([b17f10a](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/b17f10a405c65535e7cd29e605d0de84d37b4fb0))
* **inbox:** decode source notices and item returns with dynamic limits ([4b69859](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/4b69859d72472ffbe8b1fce6076c9f9f4dcb5ef8))
* **items:** add safe inventory workflows and lossless properties ([b39d000](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/b39d000ae152736d5d80fa0a6dd8feeb4a97bdd1))
* **marketplace:** add ten explicit app routes and original intent recovery ([03a1184](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/03a118404f72f912fc6f1a56e18888fa8f9d9d0e))
* **matches:** add explicit Godot turn and ranked lifecycle ([fed96fe](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/fed96fe57b28abd48c5c2d3a9e1ed732e0247838))
* **realtime:** add bounded Godot subscriptions and resync (TASK-995) ([1e4b8cc](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/1e4b8cc60797cc9e55a08ea1b3659a1ca26fbdf9))
* **shared-objects:** add Godot REST and durable samples ([39e05fd](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/39e05fdc08d943eb08f8a81d2f900a6cab5c1f87))
* **values:** add session-bound player values manager ([a177093](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/a1770932eb04b0d8eaf684992562fcb22ac498ae))


### Performance Improvements

* reuse identical Groups metadata token comparisons ([0fcf6b2](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/0fcf6b2127a05f94fe02a8cb4a6ddde085fa82ef))

# [1.10.0](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/compare/v1.9.0...v1.10.0) (2026-10-11)


### Features

* **cloud-save:** revision-checked saves for several devices ([26d9f8d](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/commit/26d9f8d3e9b55a39245722140391c0d5e9bd6b3b))

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
