# Avisos y créditos

Este proyecto es una **preservación local sin ánimo de lucro** de Ninja Saga. No está
afiliado, patrocinado ni aprobado por los creadores o titulares originales del juego.

## Propiedad intelectual

- **Ninja Saga** y todos sus elementos (cliente Flash, SWFs, gráficos, sonidos, textos,
  datos del juego, nombres y logotipos) pertenecen a sus creadores y titulares originales.
- El cliente y los datos se incluyen únicamente para que el juego pueda ejecutarse en
  local con fines de preservación y estudio.
- No se concede ninguna licencia sobre esos materiales. No los redistribuyas como si
  fueran tuyos ni los uses comercialmente.
- Si eres titular de derechos y quieres que se retire algún contenido, abre un issue en
  el repositorio y se atenderá lo antes posible.

## Servidor privado y volcado original

- [`pseudownload/Ninja-Saga-Private-Server`](https://github.com/pseudownload/Ninja-Saga-Private-Server):
  framework de servidor privado, cliente personalizado y datos base.
- [`online-9/ninja-saga-code-dumps`](https://github.com/online-9/ninja-saga-code-dumps):
  volcado original de SWFs y paneles. No se incluye en este repositorio; se conserva
  localmente en `repo/` y se puede obtener del proyecto original.

## Herramientas y bibliotecas

| Componente | Uso | Licencia / enlace |
|---|---|---|
| [Ruffle](https://ruffle.rs/) | Reproductor Flash en el navegador | MIT / Apache-2.0 |
| [JPEXS FFDec](https://www.free-decompiler.com/flash/) | Decompilar/recompilar SWFs | Ver el proyecto |
| [Laravel](https://laravel.com/) | Servidor y gateway AMF | MIT |
| [MariaDB](https://mariadb.org/) | Base de datos | GPLv2 |
| [PHP](https://www.php.net/) | Intérprete del servidor | PHP License 3.01 |
| [Node.js](https://nodejs.org/) | Proxy HTTPS y assets | MIT |
| [Composer](https://getcomposer.org/) | Dependencias PHP (vendor incluido) | MIT |

Las dependencias de `vendor/` conservan sus propios archivos de licencia. No se han
modificado sus avisos de copyright.

## Fuentes

El cliente original usa fuentes de sistema que Ruffle no tiene. Para que los textos se
rendericen se incluyen Arial, Arial Unicode, Verdana, Franklin Gothic y Noto Sans. Arial,
Arial Unicode, Verdana y Franklin Gothic son propiedad de Microsoft y se incluyen
únicamente para reproducir la tipografía del cliente en local. Noto Sans pertenece a
Google y se distribuye bajo SIL Open Font License.

Si redistribuyes este proyecto, revisa las licencias de las fuentes y considera
reemplazarlas por alternativas libres.

## Código propio

Los lanzadores, el instalador de Windows, el proxy HTTPS, los parches y la documentación
originales de este montaje se publican bajo la licencia MIT incluida en `LICENSE`.

## Marcas

Los nombres Ninja Saga, Facebook, Adobe, AIR, Flash, Chrome, Edge, Windows, macOS, PHP,
MariaDB, Node.js, Laravel y Ruffle se usan solo para describir el proyecto o su
compatibilidad. No implican patrocinio ni afiliación.
