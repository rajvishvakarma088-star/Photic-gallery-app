package com.example.photicgallery

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import coil.Coil
import coil.request.ImageRequest
import com.google.ar.core.Config
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.node.ImageNode

class ARViewerActivity : FragmentActivity() {

    private lateinit var arSceneView: ARSceneView
    private lateinit var progressBar: ProgressBar
    private lateinit var instructionText: TextView
    private lateinit var closeButton: ImageButton

    private var placedNode: AnchorNode? = null
    private var placedImageNode: ImageNode? = null
    private var loadedBitmap: Bitmap? = null
    private var threeFingerLastAngle: Float? = null
    private var twoFingerLastAngle: Float? = null
    private var twoFingerLastSpan: Float? = null
    private val CAMERA_PERMISSION_CODE = 1002

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val rootLayout = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        arSceneView = ARSceneView(this).apply {
            id = View.generateViewId()
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            sessionConfiguration = { _, config ->
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
                config.focusMode = Config.FocusMode.AUTO
                config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
            }
        }
        rootLayout.addView(arSceneView)

        progressBar = ProgressBar(this).apply {
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER }
        }
        rootLayout.addView(progressBar)

        instructionText = TextView(this).apply {
            text = "Tap a surface to place your image"
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#99000000"))
            setPadding(40, 20, 40, 20)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = 120
            }
        }
        rootLayout.addView(instructionText)

        closeButton = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            background = null
            setColorFilter(Color.WHITE)
            setOnClickListener { finish() }
            layoutParams = FrameLayout.LayoutParams(120, 120).apply {
                gravity = Gravity.TOP or Gravity.START
                topMargin = 80
                leftMargin = 40
            }
        }
        rootLayout.addView(closeButton)

        setContentView(rootLayout)

        val imagePath = intent.getStringExtra("imagePath")
        if (imagePath.isNullOrEmpty()) { showErrorAndFinish(); return }
        loadImage(imagePath)
    }

    private fun loadImage(path: String) {
        progressBar.visibility = View.VISIBLE
        if (path.startsWith("http://") || path.startsWith("https://")) {
            val imageLoader = Coil.imageLoader(this)
            val request = ImageRequest.Builder(this)
                .data(path)
                .target(
                    onStart = { progressBar.visibility = View.VISIBLE },
                    onSuccess = { result ->
                        progressBar.visibility = View.GONE
                        setupAR((result as BitmapDrawable).bitmap)
                    },
                    onError = { progressBar.visibility = View.GONE; showErrorAndFinish() }
                )
                .build()
            imageLoader.enqueue(request)
        } else {
            try {
                val bitmap = BitmapFactory.decodeFile(path)
                progressBar.visibility = View.GONE
                if (bitmap != null) setupAR(bitmap) else showErrorAndFinish()
            } catch (e: Exception) {
                progressBar.visibility = View.GONE
                showErrorAndFinish()
            }
        }
    }

    private fun setupAR(bitmap: Bitmap) {
        loadedBitmap = bitmap
        instructionText.visibility = View.VISIBLE

        arSceneView.setOnTouchListener { _, event ->

            // ── 3-FINGER: Y-axis spin (left/right rotation flat on surface) ──────
            if (event.pointerCount == 3) {
                val cx = (event.getX(0) + event.getX(1) + event.getX(2)) / 3f
                val cy = (event.getY(0) + event.getY(1) + event.getY(2)) / 3f
                val angle = Math.toDegrees(
                    Math.atan2((event.getY(0) - cy).toDouble(), (event.getX(0) - cx).toDouble())
                ).toFloat()

                when (event.actionMasked) {
                    MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_DOWN -> {
                        threeFingerLastAngle = angle
                        twoFingerLastAngle = null
                    }
                    MotionEvent.ACTION_MOVE -> {
                        threeFingerLastAngle?.let { last ->
                            var delta = angle - last
                            if (delta > 180f) delta -= 360f
                            if (delta < -180f) delta += 360f
                            placedImageNode?.let { node ->
                                node.rotation = Float3(node.rotation.x, node.rotation.y + delta * 0.5f, node.rotation.z)
                            }
                            threeFingerLastAngle = angle
                        }
                    }
                    MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                        threeFingerLastAngle = null
                }
                return@setOnTouchListener true
            }

            // ── 2-FINGER: Zoom (span ratio) + Z-Roll (when twist dominant) ────────
            if (event.pointerCount == 2) {
                val dx = event.getX(1) - event.getX(0)
                val dy = event.getY(1) - event.getY(0)
                val angle = Math.toDegrees(Math.atan2(dy.toDouble(), dx.toDouble())).toFloat()
                val span  = Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()

                when (event.actionMasked) {
                    MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_DOWN -> {
                        twoFingerLastAngle = angle
                        twoFingerLastSpan  = span
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val lastAngle = twoFingerLastAngle ?: angle
                        val lastSpan  = twoFingerLastSpan  ?: span

                        // ── ZOOM: always apply from span ratio ────────────────────────
                        if (lastSpan > 0f) {
                            val scaleRatio = span / lastSpan
                            placedImageNode?.let { node ->
                                val cur = node.scale.x
                                val next = (cur * scaleRatio).coerceIn(0.1f, 20f)
                                node.scale = Float3(next, next, next)
                            }
                        }

                        // ── Z-ROTATION: only when twist is clearly dominant ─────────────
                        var deltaAngle = angle - lastAngle
                        if (deltaAngle >  180f) deltaAngle -= 360f
                        if (deltaAngle < -180f) deltaAngle += 360f
                        val absDelta = Math.abs(deltaAngle)
                        val absSpanChange = Math.abs(span - lastSpan)
                        // Fire rotation only if angle change is large relative to span change
                        if (absDelta > 2f && absDelta > absSpanChange * 0.25f) {
                            placedImageNode?.let { node ->
                                node.rotation = Float3(
                                    node.rotation.x, node.rotation.y,
                                    node.rotation.z + deltaAngle * 0.5f
                                )
                            }
                        }

                        twoFingerLastAngle = angle
                        twoFingerLastSpan  = span
                    }
                    MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        twoFingerLastAngle = null
                        twoFingerLastSpan  = null
                    }
                }
                return@setOnTouchListener true // we handle everything, consume event
            }

            // ── 1-FINGER TAP: Place the image on a detected surface ───────────────
            // Guard pointerCount == 1 to prevent the 2-finger lift event triggering a place
            if (event.pointerCount == 1 && event.action == MotionEvent.ACTION_UP) {
                try {
                    val hitResult = arSceneView.frame?.hitTest(event)?.firstOrNull()
                    if (hitResult != null) {
                        val anchor = hitResult.createAnchor()
                        if (placedNode == null) {
                            val anchorNode = AnchorNode(arSceneView.engine, anchor)
                            val imageNode = ImageNode(arSceneView.materialLoader, bitmap).apply {
                                isEditable = true
                                isRotationEditable = false
                                isScaleEditable = false  // we handle scale manually below
                                isPositionEditable = true
                                editableScaleRange = 0.1f..20.0f
                                smoothTransformSpeed = 8f
                            }
                            anchorNode.addChildNode(imageNode)
                            arSceneView.addChildNode(anchorNode)
                            placedNode = anchorNode
                            placedImageNode = imageNode
                            runOnUiThread { instructionText.visibility = View.GONE }
                        } else {
                            placedNode?.anchor = anchor
                        }
                    }
                } catch (e: Exception) {
                    // Ignore transient ARCore hitTest/createAnchor exceptions
                }
            }
            false
        }
    }

    private fun showErrorAndFinish() {
        Toast.makeText(this, "Could not load image for AR", Toast.LENGTH_SHORT).show()
        finish()
    }

    private fun checkCameraPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_CODE)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_CODE && grantResults.isNotEmpty() && grantResults[0] != PackageManager.PERMISSION_GRANTED) {
            Toast.makeText(this, "Camera permission is required for AR", Toast.LENGTH_LONG).show()
            finish()
        }
    }

    override fun onResume() {
        super.onResume()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
            checkCameraPermission()
    }

    override fun onDestroy() {
        super.onDestroy()
        try { loadedBitmap?.let { if (!it.isRecycled) it.recycle() } } catch (e: Exception) { }
    }
}
