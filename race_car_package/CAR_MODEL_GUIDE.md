# 3D-модель болида: инструкция для агента

Модель — стилизованный «игрушечный» болид с открытыми колёсами: укороченные пропорции, крупные колёса, своя ливрея без чужих брендов. Предназначена для iOS-игры (вид сверху или под углом), где машина едет по траектории, которую игрок рисует пальцем.

## Файлы

| Файл | Назначение |
|---|---|
| `race_car.usdz` | Основная модель для iOS (RealityKit / SceneKit / AR Quick Look). Есть оба состояния стоп-сигнала |
| `race_car.glb` | Та же модель в glTF 2.0 (Unity через glTFast, Godot, Blender, three.js) |
| `race_car_brake_off.usdz`, `race_car_brake_off.glb` | Вариант без узла горящего стоп-сигнала (только выключенный) |
| `race_car_obj.zip` | OBJ + MTL, универсальный формат без иерархии узлов |
| `build_car_toy.py` | Процедурный генератор модели (исходник) |
| `export_usd.py` | Конвертер GLB → USDZ |
| `render.py` | Программный рендер превью без GPU (для проверки) |
| `preview.png` | Превью стоп-сигнала (выкл / вкл) |

Для игры на iOS используй `race_car.usdz`.

## Система координат и размеры

- Единицы — **метры**, масштаб 1:1.
- **Y — вверх**, **нос машины смотрит в +Z**, левый борт (со стороны пилота) — **+X**.
- Начало координат — на земле (y = 0), примерно по центру машины.
- Габариты: длина ≈ 3.84 м (z от −1.89 до +1.94), ширина ≈ 2.29 м, высота ≈ 1.26 м.
- Около 89.6 тыс. треугольников, 124 меш-узла.

**Важно для RealityKit:** «вперёд» у сущностей там −Z, а `look(at:)` направляет −Z на цель. Поэтому оберни модель в родительскую сущность с поворотом на 180° вокруг Y (пример ниже) и управляй движением через родителя.

## Иерархия узлов

```
car                        корень
├── body                   весь кузов (статичен относительно car)
│   ├── chassis_top, chassis_side, sidepod_*, airbox_*, halo_hoop, halo_pillar,
│   │   fw_* (переднее крыло), rw_* (заднее крыло), floor, diffuser, susp_*, helmet, visor, ...
│   ├── rain_light_housing, rain_light_lens, rain_light_mount
│   ├── rain_light_leds_off   светодиоды стоп-сигнала, выключенные (серые) — видны всегда
│   └── rain_light_leds_on    светодиоды горящие (красные, emissive) — лежат поверх _off
├── wheel_FL               переднее левое  (x=+0.88, y=0.43, z=+1.095)
├── wheel_FR               переднее правое (x=−0.88, y=0.43, z=+1.095)
├── wheel_RL               заднее левое    (x=+0.88, y=0.43, z=−1.243)
└── wheel_RR               заднее правое   (x=−0.88, y=0.43, z=−1.243)
    └── wheel_XX_tyre, _rim, _rim_lip, _cover, _inner, _brake_drum, _stripe_in, _stripe_out
```

Парные детали называются с суффиксами `_L` / `_R` (например `sidepod_top_L`).

### Колёса

- Pivot каждого узла `wheel_*` — в центре ступицы. Ось вращения качения — **X** узла.
- Радиус шины — **0.43 м**. Угловая скорость качения: `ω = v / 0.43` (рад/с).
- Положительный поворот вокруг +X катит колесо вперёд (+Z модели).
- Поворот руля — вращение передних узлов (`wheel_FL`, `wheel_FR`) вокруг **Y**. Положительный угол поворачивает колесо носом влево (к +X).
- Меняй только `orientation` или `rotation` узла колеса, позицию не трогай: она задаёт место колеса на машине.

### Стоп-сигнал

- `rain_light_leds_off` (серые) видны всегда. `rain_light_leds_on` (красные, светящиеся) лежат на 2.5 мм ближе к зрителю и полностью их перекрывают.
- Включить или выключить сигнал = показать или скрыть **только** `rain_light_leds_on`.
- В USD у материала `led` задан `emissiveColor`. Если в каком-то рендерере он не светится, назначь этому узлу unlit-материал красного цвета.

## Материалы

Текстур и UV-развёртки **нет**: цвет задан PBR-материалами, по одному на тип детали. Чтобы перекрасить машину, достаточно заменить материал.

| Материал | Где | Цвет |
|---|---|---|
| `red` | верх кузова, понтоны, гребень, стенки боковых воздухозаборников | красный |
| `white` | бока, переднее и заднее крыло | белый |
| `navy` | верхний воздухозаборник, зеркала, закрылки | синий |
| `carbon` | днище, подвеска, halo, корпус стоп-сигнала | почти чёрный |
| `inlet` | дно воздухозаборников, кокпит | чёрный матовый |
| `tyre`, `rim`, `stripe` | шина, диск, полоса на боковине | чёрный / тёмно-серый / жёлтый |
| `helmet`, `visor` | шлем, визор | красный / чёрный глянец |
| `camera` | бортовая камера на airbox | жёлтый |
| `lens` | подложка стоп-сигнала | чёрный |
| `led_off` / `led` | светодиоды выкл / вкл | серый / красный emissive |

Для нескольких машин разного цвета клонируй модель и меняй материалы `red`, `navy` и `white` у нужных сущностей.

## Пример: RealityKit (Swift)

```swift
import RealityKit

final class CarEntity {
    let root = Entity()                 // этим управляет игра: позиция и курс
    private let model: Entity
    private let wheels: [Entity]
    private let frontWheels: [Entity]
    private let brakeOn: Entity?
    private var wheelAngle: Float = 0
    private let tyreRadius: Float = 0.43

    init() throws {
        model = try Entity.load(named: "race_car")        // race_car.usdz в бандле
        // Модель смотрит в +Z, RealityKit — в −Z: разворачиваем, чтобы root.look(at:) работал
        model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        root.addChild(model)

        wheels = ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"].compactMap { model.findEntity(named: $0) }
        frontWheels = ["wheel_FL", "wheel_FR"].compactMap { model.findEntity(named: $0) }
        brakeOn = model.findEntity(named: "rain_light_leds_on")
        brakeOn?.isEnabled = false
    }

    /// speed — м/с, steer — радианы (+ влево), dt — секунды кадра
    func update(speed: Float, steer: Float, braking: Bool, dt: Float) {
        wheelAngle += speed / tyreRadius * dt
        let roll = simd_quatf(angle: wheelAngle, axis: [1, 0, 0])
        let yaw  = simd_quatf(angle: steer, axis: [0, 1, 0])
        for w in wheels {
            w.orientation = frontWheels.contains(where: { $0 === w }) ? yaw * roll : roll
        }
        brakeOn?.isEnabled = braking
    }
}
```

Движение по траектории пальца: ставь `root.position` в точку кривой и вызывай `root.look(at: следующая_точка, from: root.position, relativeTo: nil)`. Угол руля оценивай по кривизне траектории, клампь примерно до ±0.4 рад.

Масштаб: модель в реальных метрах. Если трасса сделана в других единицах, меняй `root.scale`, а не геометрию.

## Unity / Godot

- **Unity:** импортируй `race_car.glb` через пакет glTFast (`com.unity.cloud.gltfast`). glTF правосторонний, импортёр сам конвертирует оси, и нос окажется в +Z, как ожидает Unity. Колёса находятся через `transform.Find("wheel_FL")` (путь может зависеть от корня импорта). Стоп-сигнал включается через `SetActive` у `rain_light_leds_on`.
- **Godot 4:** импортируй `race_car.glb` напрямую. Нос в +Z, а «вперёд» в Godot — −Z, поэтому разверни модель на 180° вокруг Y внутри родительского `Node3D`.

## Как изменить или пересобрать модель

Модель целиком генерируется кодом. Ручного редактирования в Blender не требуется, но оно возможно (открой GLB).

```bash
pip install trimesh numpy shapely mapbox_earcut usd-core
mkdir -p out out_off
python3 build_car_toy.py out                      # → out/race_car.glb (со стоп-сигналом вкл/выкл)
BRAKE_LIGHT=off python3 build_car_toy.py out_off  # → вариант без горящих LED
python3 export_usd.py out                         # → out/race_car.usdz (+ .usdc и .obj)
python3 render.py ...                             # опционально: превью без GPU (см. код)
```

Основные параметры в `build_car_toy.py`:
- `MAT` (в начале файла) — цвета, металличность и шероховатость материалов.
- `KZ`, `KX`, `KY` (перед `build_scene`) — «мультяшность»: сжатие по длине, ширина и высота кузова.
- `TYRE_R`, `FRONT_W`, `REAR_W`, `FRONT_X`, `REAR_X` — размер колёс и колея.
- Секции кузова: `CH` (монокок и нос), `PODS` (понтоны), `AB` (airbox). Каждая строка — сечение `(z, x_центр, y_низ, y_верх, полуширина)`.
- Halo — функция `halo_pts()` и `oval_tube(...)` (параметры `r_wide`, `r_thin`).

После любых изменений пересобери GLB и USDZ и проверь результат на превью: геометрия процедурная, поэтому изменение секций может создать пересечения деталей.

## Ограничения

- Нет UV и текстур. Для наклеек и номеров нужно сделать UV-развёртку в Blender.
- Нет коллайдеров. Для физики используй простой бокс примерно 2.3 × 1.0 × 3.8 м, геометрия для этого не нужна.
- Нет LOD. Если на сцене много машин, можно уменьшить число сегментов колёс в `wheel()` и плотность лофтов (параметры `n`, `sub`).
