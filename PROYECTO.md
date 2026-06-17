# Documentacion tecnica del proyecto

Resumen del proyecto: que es, las decisiones metodologicas clave, los hallazgos
principales, como reproducirlo y el trabajo pendiente.

## 1. Que es

Analisis estadistico reproducible de la **participacion ciudadana en salud** en
Chile, a partir de los Resumenes Estadisticos Mensuales (REM 2025) del DEIS-MINSAL.
La seccion A19b reune tres familias de actividad distintas; se analizan **seccion
por seccion** (bloques A, B y C) con un motor reutilizable, y se sintetizan en
indicadores de **auditoria social** con denominador poblacional.

- Repositorio: https://github.com/javierverabravo/participacion-salud-rem
- Tablero: https://javierverabravo.github.io/participacion-salud-rem/

**Tesis:** la decision de registrar es un rasgo **institucional** (del
establecimiento) en las tres secciones, pero el **territorio y la pobreza no pesan
igual**: son mas relevantes en OIRS y, sobre todo, en satisfaccion usuaria.

---

## 2. Pipeline

El pipeline analiza la A19b seccion por seccion (bloques A / B / C) con un motor de
funciones reutilizable, agrega CASEN 2024 y un denominador FONASA, produce
indicadores de auditoria social, y suma analisis complementarios (procedencia,
diagnostico, A06 salud mental y monitoreo del ano en curso).

### Scripts (`R/`)

```
00_descarga.R          Descarga REM del ano + base maestra de establecimientos
01_procesamiento.R     Crosswalk A19b (diccionario del ano), bloques A/B/C, tabla larga,
                       universo estab x mes, validaciones y diccionario del dato
02_datos_comunales.R   Pobreza comunal CASEN 2024 (ingresos + multidim., SAE)
03_fonasa_inscritos.R  Denominador poblacional FONASA (lector flexible; degrada con NA)
04_engine.R            Motor por bloque: panel, KPIs, cobertura, serie, equidad,
                       subsecciones, hurdle mixto (glmer+lmer), multinivel 3 niveles,
                       espacial, tipologias. tryCatch + modelo_estado.csv; isSingular.
05_indicadores.R       Indicadores de auditoria social (I_fa, T_se, I_dd, I_ci + extras)
06/07/08_analisis_*.R  Corren el motor sobre A / B / C
09_sintesis.R          Comparativo A/B/C, tipologias cross-tema, territorio, indicadores
10_run_all.R           Maestro: ejecuta 00 a 09 + pasos complementarios 10 a 13
manifiesto_datos.R     Manifiesto de procedencia (huellas sha256 de los insumos)
diagnostico_datos.R    Caracterizacion empirica del dato (exceso de ceros, sobredispersion)
12_a06_salud_mental.R  Complementario: A06 C.1 (coordinacion comunitaria en salud mental)
                       y su solape con la participacion A19b (ver EVALUACION_A06.md)
11_monitoreo_2026.R    Monitoreo multianual del ano preliminar: comparacion del mismo
                       periodo, proyeccion de cierre y trayectoria 2024-2025-2026 (A y B)
exploratorio/          Scripts de fases previas (archivados)
```

`10_run_all.R` ejecuta 00 a 09 y luego, en `tryCatch`, los pasos 10 a 13 (manifiesto,
diagnostico, A06 y monitoreo); si falta un insumo, ese paso se omite con aviso sin
abortar. Flags: `REM_PAR`, `REM_SENS`, `REM_DEP`, `REM_FAST`, `REM_A06`, `REM_MON`.

Los productos quedan en `productos/` (no se versionan; el tablero en `docs/` si).

---

## 3. Decisiones tecnicas clave

- **Codificacion CSV = UTF-8 con BOM** (no Latin-1). Lectura con `data.table::fread`,
  separador `;`, `CodigoPrestacion` como texto.
- **El subregistro esta en filas ausentes**, no en NA. No se colapsan los NA a 0. El
  panel completo (establecimiento x mes) se reconstruye en `01_procesamiento.R`.
- **valor_total = Col01** es el conteo principal de cada seccion (en A, participantes;
  en B y C, actividades o sesiones). El total de participantes "ambos sexos" de B y C
  vive en otra columna y se usa solo para equidad.
- **Modelo hurdle, descomposicion en dos partes** (`glmer` logistica para la barrera +
  `lmer` log-lineal para la intensidad). El `glmmTMB` de objeto unico no converge por la
  cola extrema. Se verifica convergencia y singularidad (isSingular).
- **Componentes de varianza (ICC, % por nivel, MOR): estimacion puntual.** Su IC por
  bootstrap es prohibitivo a esta escala; la incertidumbre de los efectos (OR) si se
  reporta con IC.
- **CASEN 2024** se auto-descarga; **FONASA** se coloca a mano (portal sin URL estable).

---

## 4. Hallazgos principales

| Indicador | A, OIRS | B, Part. social | C, Satisfaccion |
|---|---:|---:|---:|
| Cobertura (% estab.) | 49,9 % | 51,1 % | 24,4 % |
| Subregistro (% estab-mes) | 60,4 % | 71,7 % | 91,6 % |
| ICC barrera (peso del establecimiento) | 93,9 % | 65,8 % | 74,3 % |
| Varianza nivel comuna | 29,1 % | 17,5 % | 4,1 % |
| OR pobreza (+10 pp) | 0,59 (ns) | 0,85 (ns) | **0,58 (p<0,001)** |

- Lo institucional domina en las tres secciones (ICC de la barrera 66 a 94 %).
- El territorio no pesa igual: B es institucional puro; A tiene componente comunal;
  C es la unica donde la pobreza comunal predice el registro.
- El subregistro crece de A a C y se aloja en filas ausentes.
- **A06 complementario:** de los establecimientos sin participacion social A19b, cerca
  del 12 % si hacen trabajo comunitario en salud mental (A06 C.1). El A19b se pierde esa
  actividad; se reporta como relacion entre dos registros, no redefiniendo el constructo.
- **Monitoreo multianual:** A (OIRS) plano 2024-2026; B (participacion social) en alza
  sostenida (fuerte crecimiento 2024 a 2025, proyeccion al alza en 2026, sobre codigos
  comparables).

---

## 5. Como reproducir

Con el repositorio clonado y R mas Quarto instalados:

1. Reconstruir el entorno: `renv::restore()` (una sola vez; ver ENTORNO.md).
2. **Corrida normal (ano del dashboard):**
   `Sys.setenv(REM_ANIO = "2025"); source("R/10_run_all.R")`.
   Hace datos, motor, bloques, sintesis, manifiesto, diagnostico y A06; el monitoreo
   se omite (2025 no es posterior a la referencia). Corrida exacta del orden de 60 a 70
   minutos.
3. **Corrida multi-ano (para el monitoreo):** una vez por ano, **terminando con el ano
   principal**, para que los archivos compartidos (productos, crosswalk, lookup) queden
   en ese ano. El monitoreo se genera en la corrida del ano preliminar y persiste
   (esta namespaced por ano):
   ```r
   Sys.setenv(REM_ANIO = "2024"); source("R/10_run_all.R")   # datos 2024
   Sys.setenv(REM_ANIO = "2026"); source("R/10_run_all.R")   # corre el monitoreo
   Sys.setenv(REM_ANIO = "2025"); source("R/10_run_all.R")   # deja todo en 2025
   ```
4. En la terminal: `quarto render` (tablero en `docs/`) y `quarto render articulo.qmd`.

---

## 6. Pendientes

- **Namespacing de productos por ano.** Hoy `productos/`, el crosswalk de prestaciones y
  el lookup de establecimientos se regeneran y se sobrescriben entre anos; por eso la
  corrida multi-ano usa la receta de "ano principal al final". El arreglo de raiz es
  separar esos artefactos por ano (subcarpetas), para que el multi-ano sea de un solo
  paso. Refactor mediano.
- **Analisis complementario A06** (en curso): integrar el hallazgo de solape al tablero y
  al articulo como relacion entre dos registros.
- **Intervalos de las componentes de varianza** (opcional): bootstrap costoso; hoy se
  reportan como estimacion puntual con chequeo de singularidad.
- Activar o actualizar GitHub Pages tras el render.
- (Mejora) Ingreso municipal (SINIM) para evaluar la hipotesis de capacidad de gestion.
