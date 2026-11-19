# 🦖 PRIMAL HUNT

> **4v1 Asymmetric Survival-Horror & Hunting Game on Roblox** (`PlaceId: 81193971554826` · `UniverseId: 10777423056` · Team Create `v149`)  
> **Pipeline 3D:** Blender 5.3 (`bmesh` + glTF 2.0 + Eevee) → Roblox Open Cloud Assets API → Strict Luau (`--!strict`)

[![Blender 5.3](https://img.shields.io/badge/3D_Pipeline-Blender_5.3-orange)](blender/)
[![Roblox Studio](https://img.shields.io/badge/Engine-Roblox_Luau_--!strict-blue)](src/)
[![Assets Approved](https://img.shields.io/badge/Open_Cloud_Assets-Approved-brightgreen)](CHANGELOG_DEVLOG_PRIMAL_HUNT.md)

---

## Principais Recursos Implementados

- **👹 Monstro Colossal Articulado (17 Juntas `Motor6D`, 100 `MeshPart`s):** Escala `22.0` → `29.7` → `38.5` studs entre Estágios 1, 2 e 3 (`1500/800` → `2600/1500` → `4200/2500`), mandíbulas com presas, lâminas de antebraço, garras em gancho, espinhos dorsais, tentáculos com arpões e **Combo M1 de 3 Golpes (`SlashCombo` 1→2→3)**.
- **💥 Destruição Dinâmica de Cenário (`MonsterDestructionServer`):** O Monstro estilhaça árvores e totens durante ataques/corrida gerando tocos quebrados 3D (`ShatteredTreeStump3D`), toras voadoras (`SplinteredLogChunk3D`), partículas e regeneração em `40s`.
- **🥚 Evolução Obrigatória no Ninho (`MonsterServer` + `MonsterClient`):** Exige estar dentro de um dos `5` Ninhos Abissais 3D (`<= 34` studs) ao atingir `100%` de energia, com Feixe Localizador (`MonsterNestHomingBeacon`) e casulo de metamorfose de `5s`.
- **🦎 Ecossistema com 10 Espécies de Fauna 3D Animadas a 60 FPS:**
  - *Pack v5:* `SwampStalkerRaptor`, `ThornbackBoar`, `BiolumMantisStalker`, `MireCrocoSnapper`, `HornedCeratopsBull`.
  - *Pack v3:* `RedGoliath`, `CoastalScavenger`, `SporeCrawler`, `AcidSpitterDrake`, `ObsidianCragback`.
  - Patas calibradas com `ExactGroundY`, `Weld`s rígidos explícitos, `Model:PivotTo` e raycast exclusivo no `Workspace.Terrain` (`54` spawns ativos, 0 animais flutuando).
- **🧭 Sonar Olfativo Corrigido (`[Q]`):** Ordenação por distância com `18` `Highlight`s + `4` Caçadores (respeitando o limite do Roblox), `10` tags `BillboardGui AlwaysOnTop`, `3` feixes `Beam` (`SonarScentTrail`) até as presas mais próximas e anel expansivo no chão.
- **🌗 Ciclo Dinâmico de Dia/Noite & Floresta Colorida:** Ciclo completo de 24h a cada `180s` (`DIA DE CAÇA` → `CREPÚSCULO` → `NOITE ABISSAL` → `ALVORADA RUBRA`), lanterna tática automática, visão noturna do Monstro e floresta colorida com copas 3D.
- **🎬 Diretor de Cutscenes 3D (`CinematicCutsceneDirector`):** Despertar do Monstro, Inserção Orbital de Dropship A.E.M., Metamorfose no Ninho e Morte Súbita / Encerramento.

---

## Estrutura do Repositório

```text
├── README.md
├── CHANGELOG_DEVLOG_PRIMAL_HUNT.md     # Notas completas para Discord & Histórico técnico
├── export_luau_scripts_for_github.py   # Extrator dos scripts Luau da sessão
├── blender/                            # Scripts Python/Blender de geração 3D (.glb + previews)
├── blender_mcp/                        # Bridge MCP usada com o Blender 5.3
├── previews/                           # Renders Eevee dos modelos gerados no Blender
├── roblox_scripts/                     # Scripts Luau (--!strict) exportados do Roblox Studio
│   ├── ServerScriptService/
│   └── StarterPlayer/
│       ├── StarterPlayerScripts/
│       └── StarterCharacterScripts/
└── *_manifest*.json / *_assets*.json   # Manifests de juntas/pivôs e Asset IDs no Open Cloud
```

Veja os detalhes completos, renders, diagramas e IDs de assets em [`CHANGELOG_DEVLOG_PRIMAL_HUNT.md`](CHANGELOG_DEVLOG_PRIMAL_HUNT.md).
