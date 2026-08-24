# Changelog

## [0.10.1](https://github.com/kosolabs/sshadow/compare/v0.10.0...v0.10.1) (2026-08-24)


### Bug Fixes

* respect the server umask when creating files and directories, fixes [#165](https://github.com/kosolabs/sshadow/issues/165) ([#314](https://github.com/kosolabs/sshadow/issues/314)) ([2c8d084](https://github.com/kosolabs/sshadow/commit/2c8d084ac531bf2eed4ea893bb6cd81bc73bd294))

## [0.10.0](https://github.com/kosolabs/sshadow/compare/v0.9.0...v0.10.0) (2026-08-22)


### Features

* require macOS 26 and centralize deployment target in Config.xcconfig ([#309](https://github.com/kosolabs/sshadow/issues/309)) ([15de875](https://github.com/kosolabs/sshadow/commit/15de8755d5e8d4c41fb9cb39cbd8a92e5108b86e))


### Bug Fixes

* watching and reconciling an individual file ([#311](https://github.com/kosolabs/sshadow/issues/311)) ([7b3ad98](https://github.com/kosolabs/sshadow/commit/7b3ad98fda4fe260e96ff994968ce63541b33395))

## [0.9.0](https://github.com/kosolabs/sshadow/compare/v0.8.1...v0.9.0) (2026-08-21)


### Features

* optimize polling frequency with idle detection ([#308](https://github.com/kosolabs/sshadow/issues/308)) ([ca06b97](https://github.com/kosolabs/sshadow/commit/ca06b979c685bc364888a5391385e1f84adc6370))
* poll watched folders every second between full polls ([#306](https://github.com/kosolabs/sshadow/issues/306)) ([00a9d82](https://github.com/kosolabs/sshadow/commit/00a9d820ef5f8d9eff051273e0df9dc8bef405b9))

## [0.8.1](https://github.com/kosolabs/sshadow/compare/v0.8.0...v0.8.1) (2026-08-20)


### Bug Fixes

* invalidate cached file content when reconcile detects remote changes ([#304](https://github.com/kosolabs/sshadow/issues/304)) ([ea56ee7](https://github.com/kosolabs/sshadow/commit/ea56ee7f298d9ae88d98a4a72fbcbade9f29240f))

## [0.8.0](https://github.com/kosolabs/sshadow/compare/v0.7.0...v0.8.0) (2026-08-19)


### Features

* add interactive connection status controls to profile UI ([#299](https://github.com/kosolabs/sshadow/issues/299)) ([1e332a8](https://github.com/kosolabs/sshadow/commit/1e332a83ba2a4e80c6cb2b5e2fe8a0935262bfe8))
* allow evicting downloaded items ([#301](https://github.com/kosolabs/sshadow/issues/301)) ([cfbca6d](https://github.com/kosolabs/sshadow/commit/cfbca6d240cbe4cad0227022dbee52aa504f2814))


### Bug Fixes

* refresh stale content on remote updates via real itemVersion ([#302](https://github.com/kosolabs/sshadow/issues/302)) ([f88037f](https://github.com/kosolabs/sshadow/commit/f88037f499d24fc9d4af03cdd0c98a4529cf3973))

## [0.7.0](https://github.com/kosolabs/sshadow/compare/v0.6.0...v0.7.0) (2026-08-19)


### Features

* go offline on permanent reconnect failures ([#296](https://github.com/kosolabs/sshadow/issues/296)) ([6f24faa](https://github.com/kosolabs/sshadow/commit/6f24faacc5992a1416d7dec282efa3c5167f9df5))
* validate private keys and unify connection validation errors ([#298](https://github.com/kosolabs/sshadow/issues/298)) ([8d4d241](https://github.com/kosolabs/sshadow/commit/8d4d2413104e5419d24c990d388956e33bebb594))

## [0.6.0](https://github.com/kosolabs/sshadow/compare/v0.5.1...v0.6.0) (2026-08-18)


### Features

* pause a connection without destroying the domain ([#290](https://github.com/kosolabs/sshadow/issues/290)) ([4884903](https://github.com/kosolabs/sshadow/commit/488490376bff51c64c753012fd0f0c2293607317))
* surface live connection status in the UI ([#295](https://github.com/kosolabs/sshadow/issues/295)) ([bd95dfe](https://github.com/kosolabs/sshadow/commit/bd95dfe249ad696e1f28190aed66d6d86a811072))


### Bug Fixes

* reconnect only after a lost connection ([#291](https://github.com/kosolabs/sshadow/issues/291)) ([4dc0518](https://github.com/kosolabs/sshadow/commit/4dc05183c0ce9dfd145df29aa72e83830b4dc36b))
* session state transitions between offline and online ([#281](https://github.com/kosolabs/sshadow/issues/281)) ([4c055aa](https://github.com/kosolabs/sshadow/commit/4c055aa0d40d03a5e8dc342e34bf52cb9b3517f9))

## [0.5.1](https://github.com/kosolabs/sshadow/compare/v0.5.0...v0.5.1) (2026-08-06)


### Bug Fixes

* bring windows to front when opening ([#280](https://github.com/kosolabs/sshadow/issues/280)) ([c7f111e](https://github.com/kosolabs/sshadow/commit/c7f111e23f457d067a1133c861294248e5e7d020))
* refactor settings to be resizable ([#278](https://github.com/kosolabs/sshadow/issues/278)) ([5da357e](https://github.com/kosolabs/sshadow/commit/5da357e547acf9326470c0a8115e15f527bec160))

## [0.5.0](https://github.com/kosolabs/sshadow/compare/v0.4.0...v0.5.0) (2026-08-06)


### Features

* reconnect with exponential backoff of transient disconnects ([#256](https://github.com/kosolabs/sshadow/issues/256)) ([0c6a17e](https://github.com/kosolabs/sshadow/commit/0c6a17e5b3cccbf694ca78727338921d5b00a80a))
* show server unreachable message in finder when ssh is disconnected ([#259](https://github.com/kosolabs/sshadow/issues/259)) ([23bc9a9](https://github.com/kosolabs/sshadow/commit/23bc9a97c56ce53e732d65c4b8a20768aa27e871))


### Bug Fixes

* misleading error message when auth fails ([#268](https://github.com/kosolabs/sshadow/issues/268)) ([ed142b4](https://github.com/kosolabs/sshadow/commit/ed142b457cdac7631db4399394bfd792d7877544))
* show app icon when any SSHadow window is open ([#267](https://github.com/kosolabs/sshadow/issues/267)) ([0dd622f](https://github.com/kosolabs/sshadow/commit/0dd622f022402b4de12589a3602cad584f65128c))

## [0.4.0](https://github.com/kosolabs/sshadow/compare/v0.3.0...v0.4.0) (2026-07-25)


### Features

* add ability to create and delete a folder ([#39](https://github.com/kosolabs/sshadow/issues/39)) ([38a2250](https://github.com/kosolabs/sshadow/commit/38a2250192ea74fbe631e846e21bfbe219ba9391))
* add about dialog with computed Build number ([#211](https://github.com/kosolabs/sshadow/issues/211)) ([88c4ec7](https://github.com/kosolabs/sshadow/commit/88c4ec7d1e324fef14baf4db0bee7e759d0b1b32))
* add display name and make list view beautiful ([#9](https://github.com/kosolabs/sshadow/issues/9)) ([a121813](https://github.com/kosolabs/sshadow/commit/a121813d1bb7fdebd6ecfaf3fd5e5d8274cd520d))
* add enable / disable toggle ([#11](https://github.com/kosolabs/sshadow/issues/11)) ([c2eaf7f](https://github.com/kosolabs/sshadow/commit/c2eaf7f17ac5bb7527e6e8ea876be03bdfcc3c6b))
* add error logging for agent client proxy connection ([#96](https://github.com/kosolabs/sshadow/issues/96)) ([4fc70e2](https://github.com/kosolabs/sshadow/commit/4fc70e25431f089a717c8144b84c58c4d3e38fb9))
* add function to compute path of item id ([#72](https://github.com/kosolabs/sshadow/issues/72)) ([9a34025](https://github.com/kosolabs/sshadow/commit/9a3402516dadbea5e6cde3d5550e4d817c3173e8))
* add function to fetch item by parentId and name ([#70](https://github.com/kosolabs/sshadow/issues/70)) ([09fba74](https://github.com/kosolabs/sshadow/commit/09fba7403771d58e7eae76e3d481733bddfc8f01))
* add function to recursively remove a directory ([#65](https://github.com/kosolabs/sshadow/issues/65)) ([597d32c](https://github.com/kosolabs/sshadow/commit/597d32c352b18fc8eba895aecad99772a8aa628d))
* add prefetch buffer to enable stutter free streaming ([#129](https://github.com/kosolabs/sshadow/issues/129)) ([ed8ea9d](https://github.com/kosolabs/sshadow/commit/ed8ea9d9a1c2206fc7e3b6a2eeef0a96bb456561))
* add support for creating symlinks ([#140](https://github.com/kosolabs/sshadow/issues/140)) ([4ae1694](https://github.com/kosolabs/sshadow/commit/4ae169461a75dae918d72db25021db6481f6c0de))
* add support for editing files ([#48](https://github.com/kosolabs/sshadow/issues/48)) ([6a2979a](https://github.com/kosolabs/sshadow/commit/6a2979a1cd71990d2b1302f36211f98b6ba3eafa))
* add support for moving and renaming files ([#43](https://github.com/kosolabs/sshadow/issues/43)) ([8cc2eef](https://github.com/kosolabs/sshadow/commit/8cc2eef3b30b9b8b095e7f78ca072535cbfbc964))
* add support for private key authentication ([#8](https://github.com/kosolabs/sshadow/issues/8)) ([b658ed9](https://github.com/kosolabs/sshadow/commit/b658ed931593327d55644ec99801940832ce35a9))
* add support for reconciling new files and changed subfolders ([#193](https://github.com/kosolabs/sshadow/issues/193)) ([45903a0](https://github.com/kosolabs/sshadow/commit/45903a0c6968cffce4318bb2215edf0636508580))
* add support for setting modify time ([#45](https://github.com/kosolabs/sshadow/issues/45)) ([564009c](https://github.com/kosolabs/sshadow/commit/564009cfbb6cc8ef334310ed03abafed57f35d55))
* add support for tracking chunks ([#77](https://github.com/kosolabs/sshadow/issues/77)) ([44d5ecf](https://github.com/kosolabs/sshadow/commit/44d5ecf5edd489856ad93d94a3f3bc346e54e431))
* add support for trashing files ([#63](https://github.com/kosolabs/sshadow/issues/63)) ([130aafa](https://github.com/kosolabs/sshadow/commit/130aafa80d6d7488acfc5769824e91169998ab55))
* add support for updating access time ([#47](https://github.com/kosolabs/sshadow/issues/47)) ([a103deb](https://github.com/kosolabs/sshadow/commit/a103debe5ffe5a84cf8f37515a4b69c628d95ce7))
* add support to manually poll for changes ([#199](https://github.com/kosolabs/sshadow/issues/199)) ([952b872](https://github.com/kosolabs/sshadow/commit/952b87217f2747b2bf3afa4bb3401448fd12e39b))
* add transfer progress to main menu ([#207](https://github.com/kosolabs/sshadow/issues/207)) ([2091ebe](https://github.com/kosolabs/sshadow/commit/2091ebebd6c1222970ad80929dedff670d7e6cd9))
* app icon ([#3](https://github.com/kosolabs/sshadow/issues/3)) ([fbebad7](https://github.com/kosolabs/sshadow/commit/fbebad7fe595674d2b37e5acc6042ea68df781ac))
* bootstrap NSXPC connection ([#223](https://github.com/kosolabs/sshadow/issues/223)) ([b518700](https://github.com/kosolabs/sshadow/commit/b518700c09494cb6d56050aff2d629b78ffde63c))
* browse folders working ([#24](https://github.com/kosolabs/sshadow/issues/24)) ([a2215a9](https://github.com/kosolabs/sshadow/commit/a2215a9a634b27fa50429074f190b96ae6e1f5d0))
* cache the entire Item as ItemModel ([#177](https://github.com/kosolabs/sshadow/issues/177)) ([3f5cedc](https://github.com/kosolabs/sshadow/commit/3f5cedca1ed42d905cc26d95aef38d66104249cb))
* connection config with working tester ([5f5d39b](https://github.com/kosolabs/sshadow/commit/5f5d39b1ae07493a87c5e7daa6576478e4f813a1))
* create / destroy SSHadowDB on enable / disable ([#69](https://github.com/kosolabs/sshadow/issues/69)) ([4b883b2](https://github.com/kosolabs/sshadow/commit/4b883b25bc6d7a6f8dddbb84706fffd39079d58c))
* custom animated icons when busy, fixes [#149](https://github.com/kosolabs/sshadow/issues/149) ([#208](https://github.com/kosolabs/sshadow/issues/208)) ([3bd52df](https://github.com/kosolabs/sshadow/commit/3bd52dfd03d4481b351027056d784f281bcc9e08))
* enable compatibility with macOS 15.0 and do CI in GitHub actions ([#44](https://github.com/kosolabs/sshadow/issues/44)) ([57961ed](https://github.com/kosolabs/sshadow/commit/57961ed91a75ce3ebaca78f7c131d9b3795e9fda))
* enable file provider ([#13](https://github.com/kosolabs/sshadow/issues/13)) ([9d23d6c](https://github.com/kosolabs/sshadow/commit/9d23d6c3db4000791f289d9fd8e77ba3960ec402))
* enable keychain to be used by group ([#21](https://github.com/kosolabs/sshadow/issues/21)) ([6b4f780](https://github.com/kosolabs/sshadow/commit/6b4f780d45581cda4d1e3793e202c2469fb04064))
* file sizes and modified time ([#25](https://github.com/kosolabs/sshadow/issues/25)) ([a179d81](https://github.com/kosolabs/sshadow/commit/a179d811b6d7c84cebfeaa458c3d8ea926f42320))
* finish reconcile functionality ([#196](https://github.com/kosolabs/sshadow/issues/196)) ([01f2622](https://github.com/kosolabs/sshadow/commit/01f262226addde0802fa844a053f0e99f328e6b6))
* implement fetch contents ([#31](https://github.com/kosolabs/sshadow/issues/31)) ([b076376](https://github.com/kosolabs/sshadow/commit/b07637640f52b93b4e9bfed1c97625ead9f0643b))
* implement speedometer and log throughput ([#62](https://github.com/kosolabs/sshadow/issues/62)) ([1aac332](https://github.com/kosolabs/sshadow/commit/1aac3320b7044e5cf9976efbf942aeb012d43f93))
* improve logging ([#75](https://github.com/kosolabs/sshadow/issues/75)) ([cd423e3](https://github.com/kosolabs/sshadow/commit/cd423e3cdfe8687c5cce8cc69ff1d05f532e8179))
* improve logging with call site information ([#50](https://github.com/kosolabs/sshadow/issues/50)) ([a29fc8b](https://github.com/kosolabs/sshadow/commit/a29fc8b7c7fbbbc20b3a4ec2bf2286d2d94f75c7))
* initial implementation of SSHItem persistence ([#68](https://github.com/kosolabs/sshadow/issues/68)) ([6ab33d7](https://github.com/kosolabs/sshadow/commit/6ab33d733a61565051d1338d358876c0c4edc160))
* initial version of fetch partial working ([#61](https://github.com/kosolabs/sshadow/issues/61)) ([297b46a](https://github.com/kosolabs/sshadow/commit/297b46a733e6d15ac7758f560a482abd88e00aa6))
* initial working enumeration ([#20](https://github.com/kosolabs/sshadow/issues/20)) ([84c3fbb](https://github.com/kosolabs/sshadow/commit/84c3fbbbb7dbe7784fc3e48f71ee53f05d77590c))
* initialize file provider module ([#5](https://github.com/kosolabs/sshadow/issues/5)) ([ba7dbf4](https://github.com/kosolabs/sshadow/commit/ba7dbf4f595224e0dcbb93c63c6acaae9efedcb6))
* introduce .sshadow/trash as the folder holding trashed data ([3d2229e](https://github.com/kosolabs/sshadow/commit/3d2229ef087fbe82ddd13d8f4a263bffeac50b1a))
* introduce .sshadow/trash as the folder holding trashed data, fixes [#161](https://github.com/kosolabs/sshadow/issues/161) ([#166](https://github.com/kosolabs/sshadow/issues/166)) ([3d2229e](https://github.com/kosolabs/sshadow/commit/3d2229ef087fbe82ddd13d8f4a263bffeac50b1a))
* introduce xpc service agent to handle background tasks ([#83](https://github.com/kosolabs/sshadow/issues/83)) ([cec3f26](https://github.com/kosolabs/sshadow/commit/cec3f26125ab9a82422511281fc9500a97f85e27))
* make symlinks non-nullable, fixes [#179](https://github.com/kosolabs/sshadow/issues/179) ([#181](https://github.com/kosolabs/sshadow/issues/181)) ([5356796](https://github.com/kosolabs/sshadow/commit/53567965fd67b702a878c91dbefce62f08f51fe7))
* menu shows rich toggles for profiles and opens finder on click, fixes [#150](https://github.com/kosolabs/sshadow/issues/150) ([#163](https://github.com/kosolabs/sshadow/issues/163)) ([250ae4f](https://github.com/kosolabs/sshadow/commit/250ae4f8bfc9dbf9a1069c8adc4cebaedbc91bce))
* migrate all IDs to SSHadowDB ([#73](https://github.com/kosolabs/sshadow/issues/73)) ([fc01b2a](https://github.com/kosolabs/sshadow/commit/fc01b2ad6eb42c723b66ccd30588fdc4e264c9d4))
* push cache down to session ([#79](https://github.com/kosolabs/sshadow/issues/79)) ([b534d53](https://github.com/kosolabs/sshadow/commit/b534d53df375eb9125f1812a8f7f834d055d201f))
* reconcile creation of new files ([#191](https://github.com/kosolabs/sshadow/issues/191)) ([653d637](https://github.com/kosolabs/sshadow/commit/653d6376a118ade062e6510bfd060cb2b508c5d9))
* reconfigure as a menubar app ([#137](https://github.com/kosolabs/sshadow/issues/137)) ([fe7c6c2](https://github.com/kosolabs/sshadow/commit/fe7c6c25973782118cd431df87c52fe8f4a6f4d5))
* seed the db with root, trash, and working set ([#71](https://github.com/kosolabs/sshadow/issues/71)) ([dfd2fc9](https://github.com/kosolabs/sshadow/commit/dfd2fc9bce22eb9d9641532bc0ac1c086eba5df5))
* show warning in finder when app is not running, fixes [#152](https://github.com/kosolabs/sshadow/issues/152) ([#160](https://github.com/kosolabs/sshadow/issues/160)) ([2b7e34d](https://github.com/kosolabs/sshadow/commit/2b7e34dbd85a130395c651862078805c6752ca6f))
* support deleting files ([#40](https://github.com/kosolabs/sshadow/issues/40)) ([d138823](https://github.com/kosolabs/sshadow/commit/d138823b08401b41295209ce29cf97d0fb50b2e4))
* support representation and reading of symlinks ([#139](https://github.com/kosolabs/sshadow/issues/139)) ([369ea2e](https://github.com/kosolabs/sshadow/commit/369ea2e7dcb8075ef9e486287c4be4a7e5013467))
* support uploading files ([#41](https://github.com/kosolabs/sshadow/issues/41)) ([80e8d1e](https://github.com/kosolabs/sshadow/commit/80e8d1e83ca51a3c3c3a8262494208b7e45cc4e4))
* test connection when extension mounts ([#18](https://github.com/kosolabs/sshadow/issues/18)) ([8a68502](https://github.com/kosolabs/sshadow/commit/8a68502ccca79e3c957c518f4130055b8f7689ae))
* use cloud drive icon in finder ([#136](https://github.com/kosolabs/sshadow/issues/136)) ([d82844e](https://github.com/kosolabs/sshadow/commit/d82844efa2d4fdf0db1e5885957269027e89ba3e))
* wire up fetch partial to the chunk cache ([#78](https://github.com/kosolabs/sshadow/issues/78)) ([672857a](https://github.com/kosolabs/sshadow/commit/672857a2e144287c11a423b4fe2daef818198d7d))
* wire-up connection config to file provider extension ([#17](https://github.com/kosolabs/sshadow/issues/17)) ([337f4b7](https://github.com/kosolabs/sshadow/commit/337f4b7fb02d7a173ed335d375529012b730d675))
* wire-up manual polling to change enumeration ([#200](https://github.com/kosolabs/sshadow/issues/200)) ([c4f5ff2](https://github.com/kosolabs/sshadow/commit/c4f5ff27df86d3363f068bb9c217faf6b6642fc8))
* wire-up periodic polling, fixes [#144](https://github.com/kosolabs/sshadow/issues/144) ([#201](https://github.com/kosolabs/sshadow/issues/201)) ([9fc22fa](https://github.com/kosolabs/sshadow/commit/9fc22faaa23558bb1ee9b8dd277e714289bee68b))
* working connection configs ([#1](https://github.com/kosolabs/sshadow/issues/1)) ([8e5b2da](https://github.com/kosolabs/sshadow/commit/8e5b2da05a40ac08b9ead83322ca90e4a7133ed9))


### Bug Fixes

* add build number output artifact ([#217](https://github.com/kosolabs/sshadow/issues/217)) ([6a9c92a](https://github.com/kosolabs/sshadow/commit/6a9c92a714cc3b28b66f924972189349935d8fca))
* agent download and add tests ([#103](https://github.com/kosolabs/sshadow/issues/103)) ([3e32764](https://github.com/kosolabs/sshadow/commit/3e32764771e950a62873a6a29ec084342860e7a4))
* build and notarize now succeeds locally via `just dmg` ([#216](https://github.com/kosolabs/sshadow/issues/216)) ([8af41fe](https://github.com/kosolabs/sshadow/commit/8af41fe3a90119614e9bfe54906cb79cd4ff0c78))
* change version to 0.1 since '-alpha' causes Xcode cloud build to fail ([#240](https://github.com/kosolabs/sshadow/issues/240)) ([99f76c7](https://github.com/kosolabs/sshadow/commit/99f76c7535300a2d69d14a07d0cff42d12b92912))
* convert xpc service to mach service so that extension can use it ([#97](https://github.com/kosolabs/sshadow/issues/97)) ([8ac36c7](https://github.com/kosolabs/sshadow/commit/8ac36c7ece40432abdb3a646aaafd57c19b6f045))
* create time falls back to modify time [#145](https://github.com/kosolabs/sshadow/issues/145) ([ce41923](https://github.com/kosolabs/sshadow/commit/ce41923f50e6f4fbc206d22579462dfed0ee800b))
* create time falls back to modify time fixes [#145](https://github.com/kosolabs/sshadow/issues/145) ([#155](https://github.com/kosolabs/sshadow/issues/155)) ([ce41923](https://github.com/kosolabs/sshadow/commit/ce41923f50e6f4fbc206d22579462dfed0ee800b))
* deletion of folders ([#66](https://github.com/kosolabs/sshadow/issues/66)) ([b7942fc](https://github.com/kosolabs/sshadow/commit/b7942fc7aea3f0ae772703a54088c661345b3457))
* disable editing of settings when config is enabled, fixes [#162](https://github.com/kosolabs/sshadow/issues/162) ([#245](https://github.com/kosolabs/sshadow/issues/245)) ([6fd75f3](https://github.com/kosolabs/sshadow/commit/6fd75f3e3ca300335ce18c8a85138eaf62325bab))
* disable profile before deleting ([#28](https://github.com/kosolabs/sshadow/issues/28)) ([9e8d583](https://github.com/kosolabs/sshadow/commit/9e8d583eb4b9d280f563100bc73ecb53f6576641))
* don't resolve symlinks on list fixes [#146](https://github.com/kosolabs/sshadow/issues/146) ([#156](https://github.com/kosolabs/sshadow/issues/156)) ([24b45d2](https://github.com/kosolabs/sshadow/commit/24b45d221ab6b2a1f79a19bbf82d4ff986e05f25))
* ensure consistent marketing version across targets ([#242](https://github.com/kosolabs/sshadow/issues/242)) ([430de67](https://github.com/kosolabs/sshadow/commit/430de671b412dcc0b7b094540b086a2701cad50b))
* ensure crash on failure to create XPCListener ([#220](https://github.com/kosolabs/sshadow/issues/220)) ([2f20ec2](https://github.com/kosolabs/sshadow/commit/2f20ec276a13036d74741bbf1cc3d10c955b90c9))
* ensure progress is correctly updated ([#56](https://github.com/kosolabs/sshadow/issues/56)) ([0c6c8f3](https://github.com/kosolabs/sshadow/commit/0c6c8f3b902638931698a4873db2ef013180a786))
* file provider ([#14](https://github.com/kosolabs/sshadow/issues/14)) ([28d21a2](https://github.com/kosolabs/sshadow/commit/28d21a240b981b3e7bf856135c9f44e290d4eeb9))
* file provider name ([#15](https://github.com/kosolabs/sshadow/issues/15)) ([ba075bb](https://github.com/kosolabs/sshadow/commit/ba075bb1e1012f6f69b7fc0df3130787f805281c))
* improve handling of connection failures and invalid private keys ([#135](https://github.com/kosolabs/sshadow/issues/135)) ([c61a4c7](https://github.com/kosolabs/sshadow/commit/c61a4c7861e7da61b81431c47183c2342ba5ff4e))
* improve handling of failed ssh connections ([#131](https://github.com/kosolabs/sshadow/issues/131)) ([90fd7b6](https://github.com/kosolabs/sshadow/commit/90fd7b63f1b1abb7e6d95e688b8a8cf5b1ac18a7))
* improve logging and progress handling ([#64](https://github.com/kosolabs/sshadow/issues/64)) ([184ec5e](https://github.com/kosolabs/sshadow/commit/184ec5e2e1bba8f0c8d2ef547d85687d7ebdf1ec))
* leaked password / passphrase on delete ([#12](https://github.com/kosolabs/sshadow/issues/12)) ([8dff00d](https://github.com/kosolabs/sshadow/commit/8dff00d2719bf78d92e1de79c9023bd88f426ff2))
* make enable() do the connection test and throw on error ([#16](https://github.com/kosolabs/sshadow/issues/16)) ([cb624b0](https://github.com/kosolabs/sshadow/commit/cb624b0c397c69c0276a8cb99561606b3e59854b))
* make icon text white ([#4](https://github.com/kosolabs/sshadow/issues/4)) ([cfbfe80](https://github.com/kosolabs/sshadow/commit/cfbfe80d9c9216673add2463705c22b62d1b3c5f))
* make XPC handshake reliable with auto retries, fixes [#232](https://github.com/kosolabs/sshadow/issues/232) ([#247](https://github.com/kosolabs/sshadow/issues/247)) ([3f5b7c6](https://github.com/kosolabs/sshadow/commit/3f5b7c65f7c66cf5159e92e678540177f3dd2a39))
* more tweaks to progress ([#57](https://github.com/kosolabs/sshadow/issues/57)) ([514d239](https://github.com/kosolabs/sshadow/commit/514d23920a52cf259f8ce661ec3249884e946a03))
* move password from SwiftData to Keychain ([#7](https://github.com/kosolabs/sshadow/issues/7)) ([f5a0525](https://github.com/kosolabs/sshadow/commit/f5a0525e1613d77771558ce995eff336009a8fa4))
* moving and rename file behavior ([#74](https://github.com/kosolabs/sshadow/issues/74)) ([8f9710c](https://github.com/kosolabs/sshadow/commit/8f9710c079eadbda3a4d5305c3d0f5ed9f4a9571))
* names of tests ([#198](https://github.com/kosolabs/sshadow/issues/198)) ([4f749e6](https://github.com/kosolabs/sshadow/commit/4f749e6da9e749da0b7408b1d0bd2180ca2b47a5))
* put version number back to 1.0 ([#218](https://github.com/kosolabs/sshadow/issues/218)) ([2e4b61c](https://github.com/kosolabs/sshadow/commit/2e4b61c820b6abc6c12d53beeb501e0d6965ebd2))
* remove sensitive data from domain.userInfo ([#22](https://github.com/kosolabs/sshadow/issues/22)) ([9f6bb42](https://github.com/kosolabs/sshadow/commit/9f6bb423ace8557e1bcf2e330e3f9db7d56c4304))
* remove unnecessary print ([532d3c0](https://github.com/kosolabs/sshadow/commit/532d3c06bdf9186496fdb045116dafa11c7dd812))
* reporting of filesystem permissions ([#142](https://github.com/kosolabs/sshadow/issues/142)) ([86fbd62](https://github.com/kosolabs/sshadow/commit/86fbd6221d8fb824addb2d66731c3ddc36cb1c18))
* reset and unregister scripts ([#233](https://github.com/kosolabs/sshadow/issues/233)) ([5a9efca](https://github.com/kosolabs/sshadow/commit/5a9efca5368eddca4c481f85e7aec7de3bcf44d4))
* security scopes reading from private key after a reboot ([#132](https://github.com/kosolabs/sshadow/issues/132)) ([492db39](https://github.com/kosolabs/sshadow/commit/492db39c86b9624326f682c9748881e522cd1ac0))
* setting permissions and add tests ([#58](https://github.com/kosolabs/sshadow/issues/58)) ([e955754](https://github.com/kosolabs/sshadow/commit/e9557548296c04bd06bf51f46bf5ce9d384b40d6))
* transfer of zero-length files ([#138](https://github.com/kosolabs/sshadow/issues/138)) ([40a3c44](https://github.com/kosolabs/sshadow/commit/40a3c44daa06087510d0da1ce0a8e14ea6cbc60b))
* try to get notarized version to work locally by resetting ([#219](https://github.com/kosolabs/sshadow/issues/219)) ([c419f43](https://github.com/kosolabs/sshadow/commit/c419f43d3a2702f5c529de409cfa315bbb75921a))
* unit tests generating files in group container, fixes [#158](https://github.com/kosolabs/sshadow/issues/158) ([#159](https://github.com/kosolabs/sshadow/issues/159)) ([0cd41a9](https://github.com/kosolabs/sshadow/commit/0cd41a97406e8de4d36269c4e2e990a1b2772f27))
* update Session to keep DomainDB in sync ([#186](https://github.com/kosolabs/sshadow/issues/186)) ([329ca98](https://github.com/kosolabs/sshadow/commit/329ca981314f52d4f8995e7f4b5838bb51947a13))
