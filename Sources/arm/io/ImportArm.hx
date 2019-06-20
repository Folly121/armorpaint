package arm.io;

import haxe.io.Bytes;
import kha.Window;
import kha.Blob;
import kha.Image;
import iron.data.MaterialData;
import iron.data.MeshData;
import iron.data.Data;
import iron.system.ArmPack;
import iron.RenderPath;
import arm.App;
import arm.Project;
import arm.ui.UITrait;
import arm.ui.UINodes;
import arm.util.Path;
import arm.util.Lz4;
import arm.util.RenderUtil;
import arm.util.ViewportUtil;
import arm.util.MeshUtil;
import arm.data.LayerSlot;
import arm.data.BrushSlot;
import arm.data.MaterialSlot;
import arm.nodes.MaterialParser;

class ImportArm {

	public static function run(project:TProjectFormat) {
		new MeshData(project.mesh_datas[0], function(md:MeshData) {
			UITrait.inst.paintObject.setData(md);
			UITrait.inst.paintObject.transform.scale.set(1, 1, 1);
			UITrait.inst.paintObject.transform.buildMatrix();
			UITrait.inst.paintObject.name = md.name;
			UITrait.inst.paintObjects = [UITrait.inst.paintObject];
			iron.App.notifyOnRender(Layers.initLayers);
			History.reset();
		});
	}

	public static function runProject(path:String) {
		Data.getBlob(path, function(b:Blob) {

			UITrait.inst.layersPreviewDirty = true;
			LayerSlot.counter = 0;
			var resetLayers = false;
			Project.projectNew(resetLayers);
			UITrait.inst.projectPath = path;
			App.filenameHandle.text = new haxe.io.Path(UITrait.inst.projectPath).file;
			Window.get(0).title = App.filenameHandle.text + " - ArmorPaint";
			var project:TProjectFormat = ArmPack.decode(b.toBytes());

			// Import as mesh instead
			if (project.version == null) {
				run(project);
				return;
			}

			UITrait.inst.project = project;
			var base = Path.baseDir(path);

			for (file in project.assets) {
				// Convert image path from relative to absolute
				var isAbsolute = file.charAt(0) == "/" || file.charAt(1) == ":";
				var abs = isAbsolute ? file : base + file;
				#if krom_windows
				var exists = Krom.sysCommand('IF EXIST "' + abs + '" EXIT /b 1');
				#else
				var exists = 1;
				// { test -e file && echo 1 || echo 0 }
				#end
				if (exists == 0) {
					UITrait.inst.showError(Strings.error2 + abs);
					var b = Bytes.alloc(4);
					b.set(0, 255);
					b.set(1, 0);
					b.set(2, 255);
					b.set(3, 255);
					var pink = Image.fromBytes(b, 1, 1);
					Data.cachedImages.set(abs, pink);
				}
				ImportTexture.run(abs);
			}

			var m0:MaterialData = null;
			Data.getMaterial("Scene", "Material", function(m:MaterialData) {
				m0 = m;
			});

			UITrait.inst.materials = [];
			for (n in project.material_nodes) {
				for (node in n.nodes) {
					if (node.type == "TEX_IMAGE") { // Convert image path from relative to absolute
						var filepath = node.buttons[0].data;
						var isAbsolute = filepath.charAt(0) == "/" || filepath.charAt(1) == ":";
						if (!isAbsolute) {
							var abs = base + filepath;
							node.buttons[0].data = abs;
						}
					}
					for (inp in node.inputs) { // Round input socket values
						if (inp.type == "VALUE") inp.default_value = Math.round(inp.default_value * 100) / 100;
					}
				}
				var mat = new MaterialSlot(m0);
				UINodes.inst.canvasMap.set(mat, n);
				UITrait.inst.materials.push(mat);

				UITrait.inst.selectedMaterial = mat;
				UINodes.inst.updateCanvasMap();
				MaterialParser.parsePaintMaterial();
				RenderUtil.makeMaterialPreview();
			}

			UITrait.inst.brushes = [];
			for (n in project.brush_nodes) {
				var brush = new BrushSlot();
				UINodes.inst.canvasBrushMap.set(brush, n);
				UITrait.inst.brushes.push(brush);
			}

			// Synchronous for now
			new MeshData(project.mesh_datas[0], function(md:MeshData) {
				UITrait.inst.paintObject.setData(md);
				UITrait.inst.paintObject.transform.scale.set(1, 1, 1);
				UITrait.inst.paintObject.transform.buildMatrix();
				UITrait.inst.paintObject.name = md.name;
				UITrait.inst.paintObjects = [UITrait.inst.paintObject];
			});

			for (i in 1...project.mesh_datas.length) {
				var raw = project.mesh_datas[i];  
				new MeshData(raw, function(md:MeshData) {
					var object = iron.Scene.active.addMeshObject(md, UITrait.inst.paintObject.materials, UITrait.inst.paintObject);
					object.name = md.name;
					object.skip_context = "paint";
					UITrait.inst.paintObjects.push(object);					
				});
			}

			// No mask by default
			if (UITrait.inst.mergedObject == null) MeshUtil.mergeMesh();
			UITrait.inst.selectPaintObject(UITrait.inst.mainObject());
			ViewportUtil.scaleToBounds();
			UITrait.inst.paintObject.skip_context = "paint";
			UITrait.inst.mergedObject.visible = true;

			UITrait.inst.resHandle.position = Config.getTextureResPos(project.layer_datas[0].res);

			if (UITrait.inst.layers[0].texpaint.width != Config.getTextureRes()) {
				for (l in UITrait.inst.layers) l.resizeAndSetBits();
				if (UITrait.inst.undoLayers != null) for (l in UITrait.inst.undoLayers) l.resizeAndSetBits();
				var rts = RenderPath.active.renderTargets;
				rts.get("texpaint_blend0").image.unload();
				rts.get("texpaint_blend0").raw.width = Config.getTextureRes();
				rts.get("texpaint_blend0").raw.height = Config.getTextureRes();
				rts.get("texpaint_blend0").image = Image.createRenderTarget(Config.getTextureRes(), Config.getTextureRes(), kha.graphics4.TextureFormat.L8, kha.graphics4.DepthStencilFormat.NoDepthAndStencil);
				rts.get("texpaint_blend1").image.unload();
				rts.get("texpaint_blend1").raw.width = Config.getTextureRes();
				rts.get("texpaint_blend1").raw.height = Config.getTextureRes();
				rts.get("texpaint_blend1").image = Image.createRenderTarget(Config.getTextureRes(), Config.getTextureRes(), kha.graphics4.TextureFormat.L8, kha.graphics4.DepthStencilFormat.NoDepthAndStencil);
				UITrait.inst.brushBlendDirty = true;
			}

			// for (l in UITrait.inst.layers) l.unload();
			UITrait.inst.layers = [];
			for (i in 0...project.layer_datas.length) {
				var ld = project.layer_datas[i];
				var l = new LayerSlot();
				UITrait.inst.layers.push(l);

				// TODO: create render target from bytes
				var texpaint = Image.fromBytes(Lz4.decode(ld.texpaint, ld.res * ld.res * 4), ld.res, ld.res);
				l.texpaint.g2.begin(false);
				l.texpaint.g2.drawImage(texpaint, 0, 0);
				l.texpaint.g2.end();
				// texpaint.unload();

				var texpaint_nor = Image.fromBytes(Lz4.decode(ld.texpaint_nor, ld.res * ld.res * 4), ld.res, ld.res);
				l.texpaint_nor.g2.begin(false);
				l.texpaint_nor.g2.drawImage(texpaint_nor, 0, 0);
				l.texpaint_nor.g2.end();
				// texpaint_nor.unload();

				var texpaint_pack = Image.fromBytes(Lz4.decode(ld.texpaint_pack, ld.res * ld.res * 4), ld.res, ld.res);
				l.texpaint_pack.g2.begin(false);
				l.texpaint_pack.g2.drawImage(texpaint_pack, 0, 0);
				l.texpaint_pack.g2.end();
				// texpaint_pack.unload();

				if (ld.texpaint_mask != null) {
					l.createMask(0, false);
					var texpaint_mask = Image.fromBytes(Lz4.decode(ld.texpaint_mask, ld.res * ld.res), ld.res, ld.res, kha.graphics4.TextureFormat.L8);
					l.texpaint_mask.g2.begin(false);
					l.texpaint_mask.g2.drawImage(texpaint_mask, 0, 0);
					l.texpaint_mask.g2.end();
					// texpaint_mask.unload();
				}

				l.maskOpacity = ld.opacity_mask;
				l.material_mask = ld.material_mask > -1 ? UITrait.inst.materials[ld.material_mask] : null;
				l.objectMask = ld.object_mask;
			}
			UITrait.inst.setLayer(UITrait.inst.layers[0]);

			UITrait.inst.ddirty = 4;
			UITrait.inst.hwnd.redraws = 2;
			UITrait.inst.hwnd1.redraws = 2;
			UITrait.inst.hwnd2.redraws = 2;

			Data.deleteBlob(path);
		});
	}

	public static function runMaterial(path:String) {
		Data.getBlob(path, function(b:Blob) {
			var project:TProjectFormat = ArmPack.decode(b.toBytes());
			if (project.version == null) { Data.deleteBlob(path); return; }
			
			var base = Path.baseDir(path);
			for (file in project.assets) {
				// Convert image path from relative to absolute
				var isAbsolute = file.charAt(0) == "/" || file.charAt(1) == ":";
				var abs = isAbsolute ? file : base + file;
				#if krom_windows
				var exists = Krom.sysCommand('IF EXIST "' + abs + '" EXIT /b 1');
				#else
				var exists = 1;
				// { test -e file && echo 1 || echo 0 }
				#end
				if (exists == 0) {
					UITrait.inst.showError(Strings.error2 + abs);
					var b = Bytes.alloc(4);
					b.set(0, 255);
					b.set(1, 0);
					b.set(2, 255);
					b.set(3, 255);
					var pink = Image.fromBytes(b, 1, 1);
					Data.cachedImages.set(abs, pink);
				}
				arm.io.ImportTexture.run(abs);
			}

			var m0:MaterialData = null;
			Data.getMaterial("Scene", "Material", function(m:MaterialData) {
				m0 = m;
			});

			for (n in project.material_nodes) {
				for (node in n.nodes) {
					if (node.type == "TEX_IMAGE") { // Convert image path from relative to absolute
						var filepath = node.buttons[0].data;
						var isAbsolute = filepath.charAt(0) == "/" || filepath.charAt(1) == ":";
						if (!isAbsolute) {
							var abs = base + filepath;
							node.buttons[0].data = abs;
						}
					}
					for (inp in node.inputs) { // Round input socket values
						if (inp.type == "VALUE") inp.default_value = Math.round(inp.default_value * 100) / 100;
					}
				}
				var mat = new MaterialSlot(m0);
				UINodes.inst.canvasMap.set(mat, n);
				UITrait.inst.materials.push(mat);

				UITrait.inst.selectedMaterial = mat;
				UINodes.inst.updateCanvasMap();
				MaterialParser.parsePaintMaterial();
				RenderUtil.makeMaterialPreview();
			}

			UITrait.inst.hwnd1.redraws = 2;
			Data.deleteBlob(path);
		});
	}
}