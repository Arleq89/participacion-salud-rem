# Gobernanza y etica de datos

Nota breve de la capa transversal de etica y gobernanza. Documenta que datos se usan,
su riesgo y los resguardos. Complementa la compuerta de publicacion (ver publicar-abierto).

## Naturaleza del dato

Todo el analisis usa **datos administrativos agregados**: conteos por establecimiento,
mes y prestacion (REM-A19b). **No hay personas identificables** ni microdatos: la unidad
es el establecimiento, no el individuo. Por eso el riesgo de reidentificacion es, en
general, bajo.

## Riesgo de celdas pequenas (equidad)

Los desgloses de equidad (sexo, identidad de genero, pueblos originarios, personas
migrantes, PRAIS) son **conteos marginales por establecimiento y subseccion**. En
establecimientos muy pequenos, una celda con un conteo bajo (por ejemplo, "1 persona
migrante") podria, en teoria, ser divulgativa al cruzarse con conocimiento local.

**Resguardo recomendado:** al publicar o difundir desgloses a nivel de establecimiento,
aplicar un **umbral de supresion** (por ejemplo, no mostrar celdas con conteo menor a 5,
o agregarlas a "menos de 5"). A nivel comunal, regional o nacional, el riesgo es
despreciable y no se requiere supresion. Los productos actuales del proyecto reportan la
equidad a nivel agregado (bloque, subseccion, region), no celda por establecimiento, por
lo que el riesgo hoy es bajo; el resguardo aplica si en el futuro se publican tablas por
establecimiento.

## Otros resguardos vigentes

- **Sin datos sensibles ni secretos en el repositorio.** `.gitignore` excluye `*.env`,
  `secrets*` y credenciales. Conviene revisar tambien el historial de git antes de hacer
  publico cualquier cambio que haya tocado credenciales.
- **Material personal fuera del repo.** La carpeta `difusion/` (posts, brief) esta
  gitignored y no se publica.
- **Datos crudos no redistribuidos.** Los REM, CASEN y FONASA no se suben (estan en
  `.gitignore`); se descargan de su fuente oficial. Ver LICENSES.md y PROCEDENCIA.csv.

## Derecho a publicar

Las fuentes son datos abiertos del Estado de Chile (DEIS, Observatorio Social, FONASA).
Los productos derivados y el codigo se licencian en LICENSES.md (CC BY 4.0 y MIT). No se
redistribuye dato de terceros sin derecho.
