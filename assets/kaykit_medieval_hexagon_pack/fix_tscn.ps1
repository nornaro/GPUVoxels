# fix_tscn.ps1
# Recursively fix .tscn files:
# - Replace .obj with .tres
# - Ensure valid Godot [gd_scene] header and structure
# - Remove uid= from [ext_resource] lines
# - Save in UTF-8 without BOM

$root = Get-Location

Get-ChildItem -Path $root -Recurse -Filter *.tscn | ForEach-Object {
	$file = $_.FullName
	$content = Get-Content $file -Raw

	# Replace .obj with .tres in paths
	$content = $content -replace "res://addons/kaykit_medieval_hexagon_pack/Assets/obj/", "res://assets/kaykit_medieval_hexagon_pack/"
	$content = $content -replace "\.obj", ".tres"

	# Remove all uid="uid://..." attributes from ext_resource lines
	$content = $content -replace 'uid="uid://[A-Za-z0-9_]+"\s*', ''

	# Detect if missing [gd_scene]
	if ($content -notmatch '^\[gd_scene') {

		# Extract any existing [sub_resource] section (collision points)
		$subresource = ""
		if ($content -match '(\[sub_resource[^\]]*\][\s\S]*)') {
			$subresource = $matches[1]
		}

		# Try to detect a mesh path
		if ($content -match 'res://assets/[^\s"]+\.tres') {
			$mesh_path = $matches[0]
		} else {
			$mesh_path = "res://assets/unknown.tres"
		}

		# Build valid structure
		$fixed = @"
[gd_scene load_steps=3 format=3 uid="uid://autofixed_$([guid]::NewGuid().ToString('N'))"]

[ext_resource type="ArrayMesh" path="$mesh_path" id="1_auto"]

$subresource

[node name="AutoFixed" type="StaticBody3D"]

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = ExtResource("1_auto")

[node name="Collision" type="CollisionShape3D" parent="."]
shape = SubResource("ConvexPolygonShape3D_auto")
"@

		# Normalize ConvexPolygonShape3D ID
		if ($fixed -notmatch 'ConvexPolygonShape3D_auto') {
			$fixed = $fixed -replace 'ConvexPolygonShape3D_[A-Za-z0-9]+', 'ConvexPolygonShape3D_auto'
		}

		# Write UTF-8 (no BOM)
		$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
		$sw = New-Object System.IO.StreamWriter($file, $false, $utf8NoBom)
		$sw.Write($fixed)
		$sw.Close()

		Write-Host "Fixed structure -> $file"
	}
	else {
		# Just update paths and strip uids
		$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
		$sw = New-Object System.IO.StreamWriter($file, $false, $utf8NoBom)
		$sw.Write($content)
		$sw.Close()

		Write-Host "Updated paths -> $file"
	}
}
