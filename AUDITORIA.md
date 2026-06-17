# Registro de correcciones y control de calidad (junio 2026)

Revision de tablero, pipeline, productos y documentos. Se documentan los problemas
detectados y su resolucion, como respaldo de la trazabilidad del proyecto.

## 1. Datos y cifras

1. **Calculo del nucleo deliberativo.** La cobertura deliberativa se dividia por los
   establecimientos que ya registran participacion social (1.523) en vez de por la red
   completa (2.982), lo que producia un valor (87,4 %) mayor que la cobertura total
   (51,1 %), imposible para un subconjunto. La cifra correcta de red es **44,6 %**. Se
   corrigio en el tablero y en `04_engine.R`.
2. **Conteo de establecimientos deliberativos.** `sub_b1_clase.csv` sumaba
   establecimientos por instancia (un centro con varias instancias se contaba varias
   veces). Se corrigio para contar establecimientos unicos.
3. **Tipologias k-means.** Dos perfiles compartian etiqueta, el termino "reclamos"
   contradecia el hallazgo de que OIRS no es reclamos, y el texto atribuia la eleccion de
   k a la silueta maxima (que esta en k=3, no en el k=4 usado). Se corrigio con etiquetas
   unicas por composicion y la k=4 declarada como particion exploratoria.
4. **Inconsistencia 2.982 vs 2.983 establecimientos.** Se unifico en 2.982.
5. **Combinaciones esperadas del panel.** El valor 35.337 era de una version previa; con
   2.982 establecimientos por 12 meses son 35.784. Se corrigio.

## 2. Tablero: estructura y presentacion

6. **Mapa de Territorio.** Fallaba por una columna de nombres de comuna inexistente en
   `chilemapas::mapa_comunas` y mezclas de objetos `sf` con `data.table`. Se reescribio el
   chunk uniendo los nombres y convirtiendo a `data.frame` antes de los merges.
7. **Sobrecarga visual.** Se reestructuro de 9 a 7 paginas, con graficos secundarios en
   pestanas.
8. **Numeros cortados en value boxes.** Formato compacto ("16,8 M").
9. **Ejes ilegibles en composicion por sexo e identidad de genero.** Dos pestanas con
   escalas propias.
10. **Graficos territoriales facetados** ilegibles en pantallas chicas. Una seccion por
    pestana.
11. **Tabla regional.** Orden por codigo antiguo y una tabla duplicada. Se unifico en una
    tabla ordenada de norte a sur.
12. **Vista movil.** Sidebar con scroll, pestanas con scroll horizontal, value boxes 2x2 y
    graficos responsivos.
13. **Codigo muerto y duplicado en `index.qmd`.** Se elimino en la reescritura.
14. **Grafico de comparacion territorial.** Mostraba solo region frente a servicio, sin la
    comuna (donde se concentra la varianza). Se incluyo la comuna.

## 3. Documentos

15. **Articulo, contradiccion interna.** La discusion describia el volumen como dominado
    por el reclamo cuando el grueso son consultas (138 mil reclamos). Se corrigio.
16. **Articulo, citas placeholder** sin respaldo. Se eliminaron.
17. **Articulo, restos de puntuacion** y ausencia del hallazgo TICs / nucleo deliberativo.
    Se corrigio y se anadio el dato de 44,6 % de red.
18. **README, parrafo de reproduccion** con una contradiccion sobre la aproximacion del
    modelo y un final truncado. Se reescribio de forma coherente.
19. **Material de difusion desactualizado** con cifras de una version previa. Se actualizo.
20. **Runbook obsoleto.** Se reescribio acorde al estado del pipeline.
21. **Articulo en PDF desactualizado.** Resuelto: se regenero con `quarto render`.
22. **Policy brief.** Observacion: verificar que sus cifras sean las vigentes antes de
    cualquier difusion.

## 4. Regeneracion de productos

Una corrida completa del pipeline (`source("R/10_run_all.R")`) regenera
`kpis_B_nucleo.csv` y `sub_b1_clase.csv` con los denominadores corregidos.
