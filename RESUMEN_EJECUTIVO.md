# Participación ciudadana en salud (REM-A19b 2025), Resumen ejecutivo

**Autor:** Javier Vera Bravo · Salud Pública, Chile ([@javierverabravo](https://github.com/javierverabravo))
**Dashboard:** https://javierverabravo.github.io/participacion-salud-rem/ · **Repo:** https://github.com/javierverabravo/participacion-salud-rem
**Datos:** Resúmenes Estadísticos Mensuales (REM) 2025, DEIS-MINSAL · 2.982 establecimientos de la red pública.

---

## La tesis en una línea

**Registrar participación es un rasgo institucional del establecimiento** (no del territorio ni
de la pobreza) en las tres secciones del A19b, pero **el peso del territorio y de la pobreza
NO es uniforme entre ellas**. Por eso conviene analizarlas por separado, no en bloque.

## Por qué por secciones

El A19b reúne tres familias de actividad que miden cosas distintas y se comportan distinto:

- **A · OIRS**, atención de usuarios: reclamos, consultas, sugerencias, solicitudes, felicitaciones.
- **B · Participación social**, consejos de desarrollo, cabildos, diálogos ciudadanos (el núcleo deliberativo que prioriza la norma).
- **C · Satisfacción usuaria y humanización**, encuestas, buzones, gestión de la experiencia.

## Hallazgos por sección

| Indicador | A · OIRS | B · Part. social | C · Satisfacción |
|---|---:|---:|---:|
| Cobertura (% establecimientos) | 49,9 % | 51,1 % | 24,4 % |
| Establecimientos que registran | 1.487 | 1.523 | 727 |
| Eventos registrados (2025) | 17,4 M | 249.767 | 119.940 |
| Subregistro estab-mes | 60,4 % | 71,7 % | 91,6 % |
| Mediana de meses con registro | 12 | 7 | 3 |
| ICC barrera (peso del establecimiento) | 93,9 % | 65,8 % | 74,3 % |
| Varianza nivel comuna | 29,1 % | 17,5 % | 4,1 % |
| Pobreza comunal (OR por +10 pp) | 0,59 (p=0,15, ns) | 0,85 (p=0,26, ns) | **0,58 (p<0,001)** |
| Mujeres entre participantes | 61,5 % | 66,5 % | 68,7 % |

**Lectura:**

1. **Lo institucional manda en las tres.** La decisión de registrar es sobre todo un rasgo del
   establecimiento (ICC de la barrera 66 a 94 %): que un centro registre o no depende de su
   gestión interna, no de dónde está.

2. **Pero el territorio no pesa igual.** La **participación social (B)** es el caso *institucional
   puro*: comuna ≈ 18 %, región < 1 %, sin clústeres espaciales y pobreza no significativa. La
   **atención OIRS (A)** tiene un componente territorial real (comuna ≈ 29 %, autocorrelación
   espacial significativa). La **satisfacción usuaria (C)** es la única sección donde la **pobreza
   comunal SÍ predice** el registro (OR 0,58; p<0,001): las comunas más pobres registran menos.

3. **El subregistro crece de A a C** (60 %, 72 %, 92 %) y no está en celdas vacías sino en
   **filas ausentes**: muchos pares establecimiento-mes simplemente no reportan. Para B, el manual
   REM indica que la sección "no presenta regla de consistencia", el subregistro está **habilitado
   por diseño** y es accionable desde el nivel central.

4. **Lo que más se mide no es lo que la norma prioriza.** El volumen de OIRS (17,4 M de eventos) está
   dominado por las **consultas**, no por los reclamos (138 mil) ni las felicitaciones (142 mil), y
   supera con creces a la deliberación (participación social, 250 mil). La participación que el sistema
   mide no es la que la norma prioriza.

## Indicadores de auditoría social (nivel nacional)

Con denominador FONASA (beneficiarios por comuna, diciembre 2025; 16,9 millones de inscritos):

- **Fricción administrativa (I_fa):** 13,1 reclamos por cada 1.000 inscritos.
- **Severidad de espera (T_se):** 46,5 % de los reclamos son por tiempos de espera.
- **Cumplimiento de plazos:** 14,7 % de los reclamos se responden fuera del plazo legal.
- **Razón felicitaciones/reclamos:** 1,03 (casi paridad entre felicitaciones y reclamos).
- **Densidad democrática (I_dd):** 10,8 participantes en participación social por cada 100 inscritos.
- **Cohesión intercultural (I_ci):** 0,86 actividades interculturales por cada 1.000 inscritos.

## Implicancias para política

- Fijar metas de registro **por establecimiento y tipo**, no por región.
- Usar los **Servicios de Salud** como unidad de gestión del registro, teniendo presente que la
  variación territorial se concentra en la **comuna** (gestión municipal): al modelar el Servicio de
  Salud como nivel jerárquico explica casi nada de la varianza, igual que la región.
- **Validar la sección de participación social** en el instrumento REM (hoy sin regla de
  consistencia) para reducir el subregistro habilitado por diseño.
- Atender el sesgo socioeconómico específico de **satisfacción usuaria**: las comunas más pobres
  registran menos.

## Cómo se llega a estas conclusiones (reproducible)

`R/10_run_all.R` ejecuta todo el pipeline en orden y deja las tablas en `productos/{A,B,C,sintesis}/`:
descarga DEIS, crosswalk A19b por bloque, datos comunales CASEN + denominador FONASA, motor de
análisis (hurdle mixto, multinivel 3 niveles, autocorrelación espacial, tipologías) por sección, 
síntesis e indicadores de auditoría social, dashboard Quarto.

*Métodos: modelos de barrera (hurdle) con efectos aleatorios por establecimiento, modelos
multinivel de tres niveles, I de Moran / LISA y agrupamiento k-means. Detalle en el README.*
