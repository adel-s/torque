<?php
//echo "<!-- Begin get_columns.php at ".date("H:i:s", microtime(true))." -->\r\n";
// this page relies on being included from another page that has already connected to db

// Create array of column name/comments for chart data selector form
// 2015.08.21 - edit by surfrock66 - Rather than pull from the column comments,
//   oull from a new database created which manages variables. Include
//   a column flagging whether a variable is populated or not.

if (isset($_POST["id"])) {
	$session_id = preg_replace('/\D/', '', $_POST['id']);
} elseif (isset($_GET["id"])) {
	$session_id = preg_replace('/\D/', '', $_GET['id']);
}

if (isset($session_id)) {
	$cur_session = $session_id;
} else $cur_session = $sids[0];

// Get raw_data for current_session
$raw_data = array();
$rawqry = mysqli_query($con, "SELECT * FROM $db_table WHERE session = '$cur_session' ORDER BY time") or die(mysqli_error($con));
// Get array of non-empty keys
while ($row = mysqli_fetch_assoc($rawqry)) {
	foreach ($row as $key => $value)
		if (substr($key, 0, 1) == "k")
			$raw_data[$key] += $value;
}

$colqry = mysqli_query($con, "SELECT id,description,type FROM $db_keys_table WHERE id like 'k%' AND populated = 1 ORDER BY description") or die(mysqli_error($con));
while ($x = mysqli_fetch_array($colqry)) {
	if (($x[2] == "float") && $raw_data[$x[0]])	{
		$coldata[] = array("colname" => $x[0], "colcomment" => $x[1]);
	}
}

$numcols = strval(count($coldata)+1);
mysqli_free_result($colqry);


$coldataempty = array();
//echo "<!-- End get_columns.php at ".date("H:i:s", microtime(true))." -->\r\n";
?>
