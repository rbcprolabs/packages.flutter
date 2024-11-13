package io.scer.pdfx

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import android.util.SparseArray
import android.view.Surface
import androidx.annotation.RequiresApi
import dev.flutter.pigeon.Pigeon
import io.flutter.BuildConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.view.TextureRegistry
import io.scer.pdfx.resources.DocumentRepository
import io.scer.pdfx.resources.PageRepository
import io.scer.pdfx.resources.RepositoryItemNotFoundException
import io.scer.pdfx.utils.CreateRendererException
import io.scer.pdfx.utils.randomFilename
import io.scer.pdfx.utils.toFile
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.lang.RuntimeException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
class Messages(private val binding : FlutterPlugin.FlutterPluginBinding,
               private val documents: DocumentRepository,
               private val pages: PageRepository) : Pigeon.PdfxApi {

    private val textures: SparseArray<TextureRegistry.SurfaceTextureEntry> = SparseArray()

    override fun openDocumentData(
        message: Pigeon.OpenDataMessage,
        result: Pigeon.Result<Pigeon.OpenReply>
    ) {
        val resultResponse = Pigeon.OpenReply()
        try {
            val documentRenderer = openDataDocument(message.data!!)
            val document = documents.register(documentRenderer)
            resultResponse.id = document.id
            resultResponse.pagesCount = document.pagesCount.toLong()
            result.success(resultResponse)
        } catch (e: IOException) {
            result.error(PdfRendererException("pdf_renderer", "Can't open file", null))
        } catch (e: CreateRendererException) {
            result.error(PdfRendererException("pdf_renderer", "Can't create PDF renderer", null))
        } catch (e: Exception) {
            result.error(PdfRendererException("pdf_renderer", "Unknown error", null))
        }
    }

    override fun openDocumentFile(
        message: Pigeon.OpenPathMessage,
        result: Pigeon.Result<Pigeon.OpenReply>
    ) {
        val resultResponse = Pigeon.OpenReply()
        try {
            val path = message.path
            val documentRenderer = openFileDocument(File(path!!))
            val document = documents.register(documentRenderer)
            resultResponse.id = document.id
            resultResponse.pagesCount = document.pagesCount.toLong()
            result.success(resultResponse)
        } catch (e: NullPointerException) {
            result.error(PdfRendererException("pdf_renderer", "Need call arguments: path", null))
        } catch (e: FileNotFoundException) {
            result.error(PdfRendererException("pdf_renderer", "File not found", null))
        } catch (e: IOException) {
            result.error(PdfRendererException("pdf_renderer", "Can't open file", null))
        } catch (e: CreateRendererException) {
            result.error(PdfRendererException("pdf_renderer", "Can't create PDF renderer", null))
        } catch (e: Exception) {
            result.error(PdfRendererException("pdf_renderer", "Unknown error", null))
        }
    }

    override fun openDocumentAsset(
        message: Pigeon.OpenPathMessage,
        result: Pigeon.Result<Pigeon.OpenReply>
    ) {
        val resultResponse = Pigeon.OpenReply()
        try {
            val path = message.path
            val documentRenderer = openAssetDocument(path!!)
            val document = documents.register(documentRenderer)
            resultResponse.id = document.id
            resultResponse.pagesCount = document.pagesCount.toLong()
            result.success(resultResponse)
        } catch (e: NullPointerException) {
            result.error(PdfRendererException("pdf_renderer", "Need call arguments: path", null))
        } catch (e: FileNotFoundException) {
            result.error(PdfRendererException("pdf_renderer", "File not found", null))
        } catch (e: IOException) {
            result.error(PdfRendererException("pdf_renderer", "Can't open file", null))
        } catch (e: CreateRendererException) {
            result.error(PdfRendererException("pdf_renderer", "Can't create PDF renderer", null))
        } catch (e: Exception) {
            result.error(PdfRendererException("pdf_renderer", "Unknown error", null))
        }
    }

    override fun closeDocument(message: Pigeon.IdMessage) {
        try {
            val id = message.id
            documents.close(id!!)
        } catch (e: NullPointerException) {
            throw PdfRendererException("pdf_renderer", "Need call arguments: id!", null)
        } catch (e: RepositoryItemNotFoundException) {
            throw PdfRendererException("pdf_renderer", "Document not exist in documents repository", null)
        } catch (e: Exception) {
            throw PdfRendererException("pdf_renderer", "Unknown error", null)
        }
    }

    override fun getPage(
        message: Pigeon.GetPageMessage,
        result: Pigeon.Result<Pigeon.GetPageReply>
    ) {
        val resultResponse = Pigeon.GetPageReply()
        try {
            val documentId = message.documentId!!
            val pageNumber = message.pageNumber!!.toInt()

            if (message.autoCloseAndroid!!) {
                documents.get(documentId).openPage(pageNumber).use { page ->
                    resultResponse.width = page.width.toDouble()
                    resultResponse.height = page.height.toDouble()
                }
            } else {
                val pageRenderer = documents.get(documentId).openPage(pageNumber)
                val page = pages.register(documentId, pageRenderer)
                resultResponse.id = page.id
                resultResponse.width = page.width.toDouble()
                resultResponse.height = page.height.toDouble()
            }

            result.success(resultResponse)
        } catch (e: NullPointerException) {
            result.error(PdfRendererException("pdf_renderer", "Need call arguments: documentId & page!", null))
        } catch (e: RepositoryItemNotFoundException) {
            result.error(PdfRendererException("pdf_renderer", "Document not exist in documents", null))
        } catch (e: Exception) {
            result.error(PdfRendererException("pdf_renderer", "Unknown error", null))
        }
    }

    override fun renderPage(
        message: Pigeon.RenderPageMessage,
        result: Pigeon.Result<Pigeon.RenderPageReply>
    ) {
        val resultResponse = Pigeon.RenderPageReply()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val pageId = message.pageId ?: run {
                    result.error(PdfRendererException("pdf_renderer", "Page ID is null", null))
                    return@launch
                }

                val width = message.width?.toInt() ?: run {
                    result.error(PdfRendererException("pdf_renderer", "Width is null", null))
                    return@launch
                }

                val height = message.height?.toInt() ?: run {
                    result.error(PdfRendererException("pdf_renderer", "Height is null", null))
                    return@launch
                }

                val format = message.format?.toInt() ?: 1
                val backgroundColor = message.backgroundColor
                val color = backgroundColor?.let { Color.parseColor(it) } ?: Color.TRANSPARENT

                val crop = message.crop ?: false
                val cropX = if (crop) message.cropX?.toInt() ?: 0 else 0
                val cropY = if (crop) message.cropY?.toInt() ?: 0 else 0
                val cropH = if (crop) message.cropHeight?.toInt() ?: 0 else 0
                val cropW = if (crop) message.width?.toInt() ?: 0 else 0

                val quality = message.quality?.toInt() ?: 100

                val page = pages.get(pageId)
                if (page == null) {
                    result.error(PdfRendererException("pdf_renderer", "Page not found for ID: $pageId", null))
                    return@launch
                }

                val tempOutFileExtension = when (format) {
                    0 -> "jpg"
                    1 -> "png"
                    2 -> "webp"
                    else -> "jpg"
                }

                val tempOutFolder = File(binding.applicationContext.cacheDir, "pdf_renderer_cache").apply {
                    mkdirs()
                }

                val tempOutFile = File(tempOutFolder, "$randomFilename.$tempOutFileExtension")

                //  background thread render
                val pageImage = page.render(
                    tempOutFile, width, height, color, format, crop, cropX, cropY, cropW, cropH, quality
                )

                withContext(Dispatchers.Main) {
                    resultResponse.path = pageImage.path
                    resultResponse.width = pageImage.width.toLong()
                    resultResponse.height = pageImage.height.toLong()
                    result.success(resultResponse)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error(PdfRendererException("pdf_renderer", "Unexpected error", e))
                }
            }
        }
    }

    override fun closePage(message: Pigeon.IdMessage) {
        try {
            val id = message.id!!
            pages.close(id)
        } catch (e: NullPointerException) {
            throw PdfRendererException("pdf_renderer", "Need call arguments: id!", null)
        } catch (e: RepositoryItemNotFoundException) {
            throw PdfRendererException("pdf_renderer", "Page not exist in pages repository", null)
        } catch (e: Exception) {
            throw PdfRendererException("pdf_renderer", "Unknown error", null)
        }
    }

    override fun registerTexture(): Pigeon.RegisterTextureReply {
        val surfaceTexture = binding.textureRegistry.createSurfaceTexture()
        val id = surfaceTexture.id().toInt()
        textures.put(id, surfaceTexture)
        val result = Pigeon.RegisterTextureReply()
        result.id = id.toLong()
        return result
    }

    override fun updateTexture(
        message: Pigeon.UpdateTextureMessage,
        result: Pigeon.Result<Void>
    ) {
        val texId = message.textureId!!.toInt()
        val pageNumber = message.pageNumber!!.toInt()
        val tex = textures[texId]
        val document = documents.get(message.documentId!!)


        document.openPage(pageNumber).use { page ->
            val fullWidth = message.fullWidth ?: page.width.toDouble()
            val fullHeight = message.fullHeight ?: page.height.toDouble()
            val destX = message.destinationX!!.toInt()
            val destY = message.destinationY!!.toInt()
            val width = message.width!!.toInt()
            val height = message.height!!.toInt()
            val srcX = message.sourceX!!.toInt()
            val srcY = message.sourceY!!.toInt()
            val backgroundColor = message.backgroundColor

            if (width <= 0 || height <= 0) {
                result.error(PdfRendererException("pdf_renderer", "updateTexture width/height == 0", null))
            }

            val mat = Matrix()
            mat.setValues(floatArrayOf((fullWidth / page.width).toFloat(), 0f, -srcX.toFloat(), 0f, (fullHeight / page.height).toFloat(), -srcY.toFloat(), 0f, 0f, 1f))

            try {
                val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                if (backgroundColor != null) {
                    bmp.eraseColor(Color.parseColor(backgroundColor))
                }
                page.render(bmp, null, mat, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                val texWidth = message.textureWidth!!.toInt()
                val texHeight = message.textureHeight!!.toInt()
                if (texWidth != 0 && texHeight != 0) {
                    tex.surfaceTexture().setDefaultBufferSize(texWidth, texHeight)
                }

                Surface(tex.surfaceTexture()).use {
                    val canvas = it.lockCanvas(Rect(destX, destY, width, height))

                    canvas.drawBitmap(bmp, destX.toFloat(), destY.toFloat(), null)
                    bmp.recycle()

                    it.unlockCanvasAndPost(canvas)
                }
                result.success(null)
            } catch (e: Exception) {
                result.error(PdfRendererException("pdf_renderer", "updateTexture Unknown error", null))
            }

        }
    }

    override fun resizeTexture(
        message: Pigeon.ResizeTextureMessage,
        result: Pigeon.Result<Void>
    ) {
        val texId = message.textureId!!.toInt()
        val width = message.width!!.toInt()
        val height = message.height!!.toInt()
        val tex = textures[texId]
        tex?.surfaceTexture()?.setDefaultBufferSize(width, height)
        result.success(null)
    }

    override fun unregisterTexture(message: Pigeon.UnregisterTextureMessage) {
        val id = message.id!!.toInt()
        val tex = textures[id]
        tex?.release()
        textures.remove(id)
    }

    private fun openDataDocument(data: ByteArray): Pair<ParcelFileDescriptor, PdfRenderer> {
        val tempDataFile = File(binding.applicationContext.cacheDir, "$randomFilename.pdf")
        if (!tempDataFile.exists()) {
            tempDataFile.writeBytes(data)
        }
        Log.d("pdf_renderer", "OpenDataDocument. Created file: " + tempDataFile.path)
        return openFileDocument(tempDataFile)
    }

    private fun openAssetDocument(assetPath: String): Pair<ParcelFileDescriptor, PdfRenderer> {
        val fullAssetPath = binding.flutterAssets.getAssetFilePathByName(assetPath)
        val tempAssetFile = File(binding.applicationContext.cacheDir, "$randomFilename.pdf")
        if (!tempAssetFile.exists()) {
            val inputStream = binding.applicationContext.assets.open(fullAssetPath)
            inputStream.toFile(tempAssetFile)
            inputStream.close()
        }
        Log.d("pdf_renderer", "OpenAssetDocument. Created file: " + tempAssetFile.path)
        return openFileDocument(tempAssetFile)
    }

    private fun openFileDocument(file: File): Pair<ParcelFileDescriptor, PdfRenderer> {
        Log.d("pdf_renderer", "OpenFileDocument. File: " + file.path)
        val fileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        return if (fileDescriptor != null) {
            val pdfRenderer = PdfRenderer(fileDescriptor)
            Pair(fileDescriptor, pdfRenderer)
        } else throw CreateRendererException()
    }
}

class PdfRendererException internal constructor(code: String?, message: String?, details: Any?) :
    RuntimeException(message) {
    private val code: String?
    private var details: Any? = null

    companion object {
        private const val TAG = "PdfRendererException#"
    }

    init {
        if (BuildConfig.DEBUG && code == null) {
            io.flutter.Log.e(TAG, "Parameter code must not be null.")
        }
        this.code = code
        if (details != null) {
            this.details = details
        }
    }
}

fun <R> Surface.use(block: (Surface) -> R): R {
    try {
        return block(this)
    }
    finally {
        this.release()
    }
}
