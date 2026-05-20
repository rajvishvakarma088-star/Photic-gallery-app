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
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.node.ImageNode

class ARViewerActivity : FragmentActivity() {

    private lateinit var arSceneView: ARSceneView
    private lateinit var progressBar: ProgressBar
    private lateinit var instructionText: TextView
    private lateinit var closeButton: ImageButton

    private var placedNode: AnchorNode? = null
    private var loadedBitmap: Bitmap? = null

    private val CAMERA_PERMISSION_CODE = 1002

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ── PROGRAMMATIC FULLSCREEN LAYOUT ─────────────────────────────────────
        val rootLayout = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        // 1. ARSceneView
        arSceneView = ARSceneView(this).apply {
            id = View.generateViewId()
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        rootLayout.addView(arSceneView)

        // 2. Loading Spinner
        progressBar = ProgressBar(this).apply {
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
            }
        }
        rootLayout.addView(progressBar)

        // 3. Instruction Overlay
        instructionText = TextView(this).apply {
            text = "Tap a surface to place"
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

        // 4. Close Button (top-left)
        closeButton = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            background = null
            setColorFilter(Color.WHITE)
            setOnClickListener { finish() }
            layoutParams = FrameLayout.LayoutParams(
                120, 120
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                topMargin = 80
                leftMargin = 40
            }
        }
        rootLayout.addView(closeButton)

        setContentView(rootLayout)

        // ── LOAD THE IMAGE ─────────────────────────────────────────────────────
        val imagePath = intent.getStringExtra("imagePath")
        if (imagePath.isNullOrEmpty()) {
            showErrorAndFinish()
            return
        }

        loadImage(imagePath)
    }

    private fun loadImage(path: String) {
        progressBar.visibility = View.VISIBLE

        if (path.startsWith("http://") || path.startsWith("https://")) {
            // Load network image using Coil
            val imageLoader = Coil.imageLoader(this)
            val request = ImageRequest.Builder(this)
                .data(path)
                .target(
                    onStart = {
                        progressBar.visibility = View.VISIBLE
                    },
                    onSuccess = { result ->
                        progressBar.visibility = View.GONE
                        val bitmap = (result as BitmapDrawable).bitmap
                        setupAR(bitmap)
                    },
                    onError = {
                        progressBar.visibility = View.GONE
                        showErrorAndFinish()
                    }
                )
                .build()
            imageLoader.enqueue(request)
        } else {
            // Load local image
            try {
                val bitmap = BitmapFactory.decodeFile(path)
                progressBar.visibility = View.GONE
                if (bitmap != null) {
                    setupAR(bitmap)
                } else {
                    showErrorAndFinish()
                }
            } catch (e: Exception) {
                progressBar.visibility = View.GONE
                showErrorAndFinish()
            }
        }
    }

    private fun setupAR(bitmap: Bitmap) {
        loadedBitmap = bitmap

        // Show instruction overlay to search for surfaces and place
        instructionText.visibility = View.VISIBLE

        // Wire tap gestures on detected planes
        arSceneView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                val hitResult = arSceneView.frame?.hitTest(event)?.firstOrNull()
                if (hitResult != null) {
                    val anchor = hitResult.createAnchor()

                    if (placedNode == null) {
                        val anchorNode = AnchorNode(arSceneView.engine, anchor)
                        val imageNode = ImageNode(arSceneView.materialLoader, bitmap).apply {
                            isEditable = true
                        }
                        anchorNode.addChildNode(imageNode)
                        arSceneView.addChildNode(anchorNode)
                        placedNode = anchorNode

                        runOnUiThread {
                            instructionText.visibility = View.GONE
                        }
                    } else {
                        // Reposition the existing node to the new surface anchor point
                        placedNode?.anchor = anchor
                    }
                }
            }
            true
        }
    }

    private fun showErrorAndFinish() {
        Toast.makeText(this, "Could not load image for AR", Toast.LENGTH_SHORT).show()
        finish()
    }

    // ── CAMERA PERMISSION & LIFECYCLE MANAGEMENT ──────────────────────────────

    private fun checkCameraPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_CODE
            )
        } else {
            resumeAR()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                resumeAR()
            } else {
                Toast.makeText(this, "Camera permission is required for AR", Toast.LENGTH_LONG).show()
                finish()
            }
        }
    }

    private fun resumeAR() {
        // SceneView 2.x handles lifecycle automatically
    }

    override fun onResume() {
        super.onResume()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            resumeAR()
        } else {
            checkCameraPermission()
        }
    }

    override fun onPause() {
        super.onPause()
        // SceneView 2.x handles lifecycle automatically
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            loadedBitmap?.let {
                if (!it.isRecycled) {
                    it.recycle()
                }
            }
        } catch (e: Exception) {
            // Ignore exceptions during cleanup
        }
    }
}
