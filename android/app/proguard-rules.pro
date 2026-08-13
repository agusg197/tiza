# El plugin google_mlkit_text_recognition referencia los cinco reconocedores de script
# —latin, chinese, devanagari, japanese, korean— desde su código Java, pero el pubspec
# sólo trae el de latín. R8 ve referencias a clases que no están en el classpath y falla
# el build de release con "Missing class".
#
# La app usa únicamente TextRecognitionScript.latin, así que esas referencias son código
# muerto que R8 va a eliminar igual. -dontwarn le dice que no son un error.
#
# La alternativa era sumar las cuatro dependencias de script que faltan, y eso agrega
# decenas de MB al APK en modelos que nunca se cargan.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
