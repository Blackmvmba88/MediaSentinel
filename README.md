# Media Sentinel

App nativa para macOS 14.2 o posterior que enumera procesos con salida de audio activa mediante Core Audio. Actualiza cada 1.5 segundos y agrupa procesos auxiliares con su app cuando puede resolver su ascendencia.

**Ver** abre la app para pausar desde su reproductor. **Cerrar** solicita cerrar toda la app. **Forzar** requiere confirmación y puede perder cambios sin guardar. Los procesos sin una app visible se revisan en Monitor de Actividad; no se terminan automáticamente.

No identifica canciones ni pestañas individuales, ni detecta videos sin salida de audio. Actividad de Core Audio no garantiza sonido audible: una app puede mantener la salida abierta con silencio. No graba audio, no usa red y no requiere permisos de micrófono ni Accesibilidad.

## Compilar

Requiere Xcode Command Line Tools con SDK macOS compatible y Swift. Ejecutar `zsh build.sh`. Resultado: `build/Media Sentinel.app`. Firma local ad hoc, sin notarización; no constituye una identidad persistente para permisos TCC.

Diagnóstico: `"build/Media Sentinel.app/Contents/MacOS/MediaSentinel" --diagnose`.

Sin dependencias externas ni datos persistentes. La instalación local se realiza copiando el bundle a `~/Applications/Media Sentinel.app`.
