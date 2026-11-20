<div align="center">

# 🦖 PRIMAL HUNT
### 4v1 Asymmetric Hunting & Survival-Horror Game

*Inspirado no clássico **Evolve Stage 2**, desenvolvido no **Roblox Studio** com pipeline 3D profissional no **Blender 5.3**, animações procedurais e física destrutiva.*

<br/>

[![Status: Em Desenvolvimento](https://img.shields.io/badge/Status-Em_Desenvolvimento_(WIP)-f1c40f?logo=git)](https://github.com/henriqueesant0s/Primal-Hunt---Game-Roblox)
[![Engine: Roblox Studio](https://img.shields.io/badge/Engine-Roblox_Studio_Luau-00a2ff?logo=roblox)](roblox_scripts/)
[![Pipeline: Blender 5.3](https://img.shields.io/badge/3D_Pipeline-Blender_5.3-ea7600?logo=blender)](blender/)
[![Gênero](https://img.shields.io/badge/G%C3%AAnero-4v1_Assim%C3%A9trico-e74c3c)]()

<br/>

</div>

> [!WARNING]
> **PROJETO EM DESENVOLVIMENTO ATIVO (Pre-Alpha / Work-in-Progress):**  
> Este jogo está sendo desenvolvido ativamente por **Henrique Santos**, **Alan Vinicius** e **Thiago Zarotti**.  
> Mecânicas de caça assimétrica, balanceamento das 4 classes de caçadores, malhas 3D e rigs esqueléticos no Blender, áudio e iluminação continuam em constante expansão e aprimoramento.

> [!NOTE]
> **Última atualização: v158** — AbyssArtKit 3D (24 malhas do Blender), combate telegrafado, deck de habilidades PC/Celular em PT-BR, spawns ajustados ao chão e **35 scripts** sincronizados. Veja [DEVLOG_V158_ABYSS_ARTKIT_AND_COMBAT_POLISH.md](DEVLOG_V158_ABYSS_ARTKIT_AND_COMBAT_POLISH.md).

---

## 👥 Equipe de Desenvolvimento & Criação

O projeto **Primal Hunt** foi concebido e desenvolvido por:
- **Henrique Santos**
- **Alan Vinicius**
- **Thiago Zarotti**

---

## 🎯 A Ideia do Projeto: O que é o Primal Hunt?

**Primal Hunt** é um jogo de ação, caça e sobrevivência tática **assimétrica 4v1** construído dentro do ecossistema do **Roblox Studio**, diretamente inspirado na experiência de **Evolve Stage 2**.

O jogo coloca **4 Caçadores especializados** (divididos em classes com papéis estratégicos complementares) contra **1 Monstro Colossal e Cruel** capaz de caçar, se alimentar, evoluir e devastar o ambiente ao seu redor.

### 🔄 O Ciclo de Gameplay (Game Loop):
1. **O Início da Caçada (Estágio 1 - Presa Furtiva):**
   O Monstro surge na arena do Estuário frágil, vulnerável e menor (`22 studs` de escala). Seu objetivo inicial é evitar confronto direto com os Caçadores, mover-se em furtividade pela densa vegetação, farejar animais com seu **Sonar Olfativo (`[Q]`)** e devorá-los para acumular energia biológica.
2. **A Busca dos Caçadores:**
   Os Caçadores chegam via Dropship orbital. Precisam ler os rastros da floresta — carcaças de animais abatidos, árvores quebradas pelo peso da criatura, ruídos de destruição e pegadas — para encurralar a fera antes que atinja seu ápice evolutivo.
3. **A Metamorfose no Ninho (Estágio 2):**
   Diferente de jogos comuns onde a evolução ocorre instantaneamente em qualquer lugar, em *Primal Hunt* o Monstro **precisa retornar a um dos 5 Ninhos Abissais** espalhados pelo mapa para iniciar seu casulo de metamorfose. Durante os 5 segundos de transformação, ele fica vulnerável, criando momentos de extrema tensão e emboscada.
4. **O Confronto Catastrófico (Estágio 3 - Predador Alfa Colossal):**
   Ao atingir o Estágio 3 (`38.5 studs`, `4200 HP`, `2500 de Armadura`), os papéis se invertem completamente: o Monstro se torna uma força implacável da natureza com força suficiente para derrubar a floresta, esmagar o Esquadrão e destruir a infraestrutura central.

---

## 🎨 Pipeline 3D Profissional: Blender 5.3 & Procedural Generation

Para garantir qualidade visual, fidelidade anatômica e desempenho que vão muito além dos limites padrão de blocos do Roblox Studio, **toda a base artística 3D foi produzida externamente via Blender 5.3** utilizando scripts procedurais em Python (`bmesh`), geração de malhas otimizadas, rigs esqueléticos e materiais com mapeamento PBR:

1. **O Monstro Colossal (Rig Articulado de 17 Juntas & 100 MeshParts):**
   - **Anatomia Predatória Ameaçadora:** Mandíbulas duplas com presas internas na faringe, lâminas curvas de executor nos antebraços, garras em gancho superiores/inferiores, placas vertebrais e tentáculos dorsais terminando em arpões biológicos.
   - **Relação de Escalas e Poder:**
     - **Estágio 1:** `22.0 studs` (~27.8m) | `1.500 HP` | `800 Armadura`
     - **Estágio 2:** `29.7 studs` (1.35x) | `2.600 HP` | `1.500 Armadura`
     - **Estágio 3:** `38.5 studs` (1.75x) | `4.200 HP` | `2.500 Armadura`
   - **Sistema de Combate M1 (Combo de 3 Golpes - `ClawSlash`):**
     - *Hit 1:* Corte horizontal direito de alta velocidade.
     - *Hit 2:* Corte cruzado esquerdo rasgando a armadura.
     - *Hit 3:* Salto e esmagamento duplo aéreo vertical com impacto sísmico radial e destruição de cenário.

2. **Fauna 3D Viva com 10 Espécies Diferentes:**
   Modeladas, riggadas e texturizadas no Blender para povoar a cadeia alimentar do mapa, cada uma com comportamentos, velocidade, rendimento de carne e posturas próprias:
   - **Predadores e Herbívoros do Pack v5:**
     - `SwampStalkerRaptor` (Bípede ágil estilo raptor)
     - `ThornbackBoar` (Javali encouraçado com espinhos dorsais)
     - `BiolumMantisStalker` (Louva-a-deus bioluminescente de emboscada)
     - `MireCrocoSnapper` (Réptil crocodiliano blindado)
     - `HornedCeratopsBull` (Megafauna pesada de chifres frontais)
   - **Predadores e Rastejadores do Pack v3:**
     - `RedGoliath` (Predador colossal carnívoro de 4 pernas)
     - `CoastalScavenger` (Carniceiro rápido de carapaça litorânea)
     - `SporeCrawler` (Insetóide rastejante de esporos)
     - `AcidSpitterDrake` (Wyrm cuspidor de toxinas corrosivas)
     - `ObsidianCragback` (Quelônio rochoso de carapaça vulcânica)

3. **Cenário Destrutível & Floresta Orgânica:**
   - Árvores do estuário e totens foram gerados com copas tridimensionais, galhos poligonais e paletas vibrantes no Blender.
   - Modelos de troncos quebrados (`ShatteredTreeStump3D`) e lascas de madeira voadoras (`SplinteredLogChunk3D`) gerados para alimentar o motor de física de destruição em tempo real.

---

## ⚙️ Arquitetura de Engenharia no Roblox Studio (Luau `--!strict`)

Todos os sistemas foram programados em Luau estrito, com separação limpa de responsabilidades entre cliente e servidor:

### 🖥️ `ServerScriptService` (Lógica Central, Física & Matchmaking):
- **`WorldBuilder.server.luau`:** Constrói o ecossistema da arena, gerencia a iluminação volumétrica, a distribuição de ninhos, cavernas e o **Ciclo Dinâmico de Dia e Noite de 180s** (Madrugada, Amanhecer, Dia de Caça, Crepúsculo e Noite Abissal).
- **`MonsterServer.server.luau`:** Controla a biologia da criatura, detecção de carcaças para alimentação, barra de energia evolutiva, validação de presença no Ninho (`<= 34 studs`) e gatilho de metamorfose.
- **`MonsterDestructionServer.server.luau`:** Motor de impacto físico. Quando o Monstro usa seu ataque pesado ou corre contra a vegetação, as árvores são partidas em tempo real, gerando toras com impulso físico, partículas e regeneração gradual após 40s.
- **`PreyManager.luau`:** Gerencia a IA da fauna, rotas de fuga, bandos, alimentação e cálculo de solo por Raycast exclusivo no `Workspace.Terrain` (garantindo que nenhum bicho flutue ou afunde).
- **`HunterCombatServer.server.luau` & `HunterClassSkills.server.luau`:** Arsenal e habilidades táticas dos Caçadores (Cúpula de Contenção, Arpões de Retenção, Dardo Rastreador, Rifle Antimaterial, Escudos e Ataques Orbitais).
- **`MatchManager.server.luau`:** Ciclo de partida, transição Lobby → Arena e estados de vitória/derrota.

### 🎮 `StarterPlayer` & `StarterCharacterScripts` (Animações & Experiência):
- **`MonsterAnimClient.client.luau`:** Controlador cinemático procedural a 60 FPS. Move as 17 juntas em tempo real via `RunService.Stepped`: ondulação de cauda, passadas com peso sísmico, inclinação em curvas, ataque de garras e animações de investida.
- **`FaunaAnimClient.client.luau`:** Animação procedural dos 10 animais da fauna (movimentação de patas, oscilação de pescoço, alertas e fuga).
- **`HorrorAtmosphere.client.luau`:** Atmosfera imersiva de terror com névoa densa, vinheta escura, lanterna tática direcional para os Caçadores e visão noturna predatória para o Monstro.
- **`MonsterClient.client.luau`:** Sistema de Sonar `[Q]` com feixes luminosos guiados por faro (`SonarScentTrail`) até as presas mais próximas e contornos brilhantes (`Highlights`).
- **`CinematicCutsceneDirector.client.luau`:** Câmeras cinematográficas dinâmicas com interpolação suave para a entrada dos Caçadores, o despertar do Monstro e a metamorfose no ninho.
- **`TacticalHUD.client.luau`:** Interface tática futurista completa, com bússola, telemetria de saúde/armadura, radar e indicadores de dano.

---

## 🎮 Controles Principais

### Como Monstro:
| Tecla / Comando | Ação |
| :--- | :--- |
| **W, A, S, D** | Movimentação / Andar |
| **Shift** | Corrida Predatória (Derruba árvores leves) |
| **Botão Esquerdo (M1)** | Combo de Garras 3-Hit (`ClawSlash` com dano em área) |
| **E (Segurar)** | Alimentar-se de carcaça / Iniciar evolução (dentro do Ninho) |
| **Q** | Sonar Olfativo (Destaca presas, carcaças e caçadores próximos) |
| **Espaço** | Salto e investida vertical |

### Como Caçador:
| Tecla / Comando | Ação |
| :--- | :--- |
| **W, A, S, D** | Movimentação |
| **Espaço (Segurar)** | Jetpack / Propulsor de elevação |
| **Botão Esquerdo (M1)** | Disparar arma primária |
| **Botão Direito (M2)** | Mira telescópica / Zoom tático |
| **1, 2, 3, 4** | Seleção de armas, armadilhas e gadgets de classe |
| **F** | Lanterna Tática de alta intensidade |

---

## 📂 Estrutura do Repositório

```text
├── README.md                                  # Documento oficial do projeto e visão de jogo
├── CHANGELOG_DEVLOG_PRIMAL_HUNT.md            # Devlog detalhado e notas para a comunidade
├── blender/                                   # Scripts de modelagem procedural, rigs e exportação (.py)
│   ├── build_colossal_monster_trees_and_destruction_v4.py
│   ├── build_cruel_monster_fauna_and_nest_v3.py
│   ├── build_diverse_fauna_pack_v5.py
│   └── ...
├── previews/                                  # Renders em alta qualidade dos modelos e cenas 3D
├── DEVLOG_V158_ABYSS_ARTKIT_AND_COMBAT_POLISH.md # Devlog da versão v158
├── roblox_scripts/                            # 35 scripts Luau (--!strict) do Studio v158
│   ├── ReplicatedStorage/                     # Módulos compartilhados (UIKit, CombatMotion, FieldDeck)
│   ├── ServerScriptService/                   # Lógica de servidor, IAs, física e economia
│   └── StarterPlayer/                         # Clientes, HUD tática, animações e cutscenes
├── textures/                                  # Texturas PBR e mapeamentos utilizados
└── *.json                                     # Manifestos técnicos de juntas, pivôs e IDs do Open Cloud
```

---

<p align="center">
  <b>Primal Hunt © 2026</b> — Desenvolvido por <b>Henrique Santos</b>, <b>Alan Vinicius</b> e <b>Thiago Zarotti</b>.<br>
  <i>Projeto em desenvolvimento ativo (Work In Progress). Todos os direitos reservados.</i>
</p>
