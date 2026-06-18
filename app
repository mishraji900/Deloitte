// filename: App.jsx
import { useState } from "react";
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Checkbox,
  Container,
  FormControlLabel,
  Grid,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  TextField,
  Typography,
} from "@mui/material";
import ExpandMoreIcon from "@mui/icons-material/ExpandMore";
console.log("validatorApi:", window.validatorApi);
const colLetterToIndex = (value) => {
  const text = String(value || "").trim().toUpperCase();
  if (!text) return NaN;
  let result = 0;
  for (const ch of text) {
    if (ch < "A" || ch > "Z") return NaN;
    result = result * 26 + (ch.charCodeAt(0) - 64);
  }
  return result;
};

const getFileValidationError = (file) => {
  const start = colLetterToIndex(file.start_col);
  const end = colLetterToIndex(file.end_col);
  const count = Number(file.number_of_columns) || 0;

  if (Number.isNaN(start) || Number.isNaN(end)) {
    return "Start column and End column must be valid Excel column letters.";
  }

  if (start > end) {
    return `Start column cannot be after End column. You entered ${file.start_col}:${file.end_col}.`;
  }

  const rangeCount = end - start + 1;
  if (count > rangeCount) {
    return `Number of headers out of bound. Selected range ${file.start_col}:${file.end_col} contains only ${rangeCount} columns.`;
  }

  return "";
};

const newColumnRule = () => ({
  column: "",
  expected_header: "",
  numeric: false,
});

const resizeColumnRules = (count, existing = []) => {
  const safeCount = Math.max(0, Number(count) || 0);
  return Array.from({ length: safeCount }, (_, index) => existing[index] || newColumnRule());
};

const newFile = () => ({
  file_path: "",
  sheet_name: "",
  header_row: 1,
  data_start_row: 2,
  data_end_row: 100,
  start_col: "A",
  end_col: "C",
  number_of_columns: 3,
  columns: resizeColumnRules(3),
});

export default function App() {
  const [files, setFiles] = useState([newFile()]);
  const [generateExcelReport, setGenerateExcelReport] = useState(true);
  const [reportOutputDir, setReportOutputDir] = useState("./output");
  const [result, setResult] = useState(null);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState("");

  const updateFile = (fileIndex, key, value) => {
    setFiles((current) =>
      current.map((file, index) => (index === fileIndex ? { ...file, [key]: value } : file))
    );
  };

  const updateNumberOfColumns = (fileIndex, value) => {
    const safeValue = Math.max(0, Number(value) || 0);
    setFiles((current) =>
      current.map((file, index) =>
        index === fileIndex
          ? {
              ...file,
              number_of_columns: safeValue,
              columns: resizeColumnRules(safeValue, file.columns),
            }
          : file
      )
    );
  };

  const updateColumn = (fileIndex, columnIndex, key, value) => {
    setFiles((current) =>
      current.map((file, index) => {
        if (index !== fileIndex) return file;
        const columns = file.columns.map((column, idx) =>
          idx === columnIndex ? { ...column, [key]: value } : column
        );
        return { ...file, columns };
      })
    );
  };

  const addFile = () => {
    setFiles((current) => [...current, newFile()]);
  };

  const browseFile = async (fileIndex) => {
    if (!window?.validatorApi?.pickExcelFile) {
      setError("Electron bridge not loaded. Open the Electron window and restart the app.");
      return;
    }

    const filePath = await window.validatorApi.pickExcelFile();
    if (filePath) updateFile(fileIndex, "file_path", filePath);
  };

  const runValidation = async () => {
    if (!window?.validatorApi?.runValidation) {
      setError("Electron bridge not loaded. Open the Electron window and restart the app.");
      return;
    }

    const fileError = files
      .map((file, index) => ({ index, error: getFileValidationError(file) }))
      .find((item) => item.error);

    if (fileError) {
      setError(`File ${fileError.index + 1}: ${fileError.error}`);
      return;
    }

    setRunning(true);
    setError("");
    setResult(null);

    try {
      const response = await window.validatorApi.runValidation({
        generate_excel_report: generateExcelReport,
        report_output_dir: reportOutputDir,
        files,
      });
      setResult(response);
    } catch (err) {
      setError(err.message || "Validation failed.");
    } finally {
      setRunning(false);
    }
  };

  const openReport = async () => {
    if (result?.reportPath && window?.validatorApi?.openReport) {
      await window.validatorApi.openReport(result.reportPath);
    }
  };

  return (
    <Container maxWidth="xl" sx={{ py: 4 }}>
      <Stack spacing={3}>
        <Typography variant="h3">Excel Validation Utility</Typography>

        <Card>
          <CardContent>
            <Stack spacing={3}>
              <Stack direction="row" spacing={2} alignItems="center" flexWrap="wrap">
                <FormControlLabel
                  control={
                    <Checkbox
                      checked={generateExcelReport}
                      onChange={(e) => setGenerateExcelReport(e.target.checked)}
                    />
                  }
                  label="Generate Excel report"
                />

                <TextField
                  label="Report output directory"
                  value={reportOutputDir}
                  onChange={(e) => setReportOutputDir(e.target.value)}
                  sx={{ minWidth: 320 }}
                />

                <Button variant="contained" onClick={runValidation} disabled={running}>
                  {running ? "RUNNING..." : "RUN VALIDATION"}
                </Button>

                <Button variant="outlined" onClick={addFile}>
                  ADD FILE
                </Button>

                {result?.reportPath && (
                  <Button variant="text" onClick={openReport}>
                    OPEN REPORT
                  </Button>
                )}
              </Stack>

              {files.map((file, fileIndex) => {
                const fileError = getFileValidationError(file);

                return (
                  <Accordion key={fileIndex} defaultExpanded>
                    <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                      <Typography>
                        File {fileIndex + 1}: {file.file_path || "Not selected"}
                      </Typography>
                    </AccordionSummary>

                    <AccordionDetails>
                      <Grid container spacing={2}>
                        <Grid item xs={12} md={6}>
                          <Stack direction="row" spacing={1}>
                            <TextField
                              fullWidth
                              label="File path"
                              value={file.file_path}
                              onChange={(e) => updateFile(fileIndex, "file_path", e.target.value)}
                            />
                            <Button variant="outlined" onClick={() => browseFile(fileIndex)}>
                              BROWSE
                            </Button>
                          </Stack>
                        </Grid>

                        <Grid item xs={12} md={2}>
                          <TextField
                            fullWidth
                            label="Sheet name"
                            value={file.sheet_name}
                            onChange={(e) => updateFile(fileIndex, "sheet_name", e.target.value)}
                          />
                        </Grid>

                        <Grid item xs={12} md={1}>
                          <TextField
                            fullWidth
                            type="number"
                            label="Header row"
                            value={file.header_row}
                            onChange={(e) =>
                              updateFile(fileIndex, "header_row", Number(e.target.value) || 0)
                            }
                          />
                        </Grid>

                        <Grid item xs={12} md={1}>
                          <TextField
                            fullWidth
                            type="number"
                            label="Data start"
                            value={file.data_start_row}
                            onChange={(e) =>
                              updateFile(fileIndex, "data_start_row", Number(e.target.value) || 0)
                            }
                          />
                        </Grid>

                        <Grid item xs={12} md={1}>
                          <TextField
                            fullWidth
                            type="number"
                            label="Data end"
                            value={file.data_end_row}
                            onChange={(e) =>
                              updateFile(fileIndex, "data_end_row", Number(e.target.value) || 0)
                            }
                          />
                        </Grid>

                        <Grid item xs={12} md={1.5}>
                          <TextField
                            fullWidth
                            label="Start col"
                            value={file.start_col}
                            onChange={(e) => updateFile(fileIndex, "start_col", e.target.value)}
                          />
                        </Grid>

                        <Grid item xs={12} md={1.5}>
                          <TextField
                            fullWidth
                            label="End col"
                            value={file.end_col}
                            onChange={(e) => updateFile(fileIndex, "end_col", e.target.value)}
                          />
                        </Grid>

                        <Grid item xs={12} md={2}>
                          <TextField
                            fullWidth
                            type="number"
                            label="Number of columns"
                            value={file.number_of_columns}
                            onChange={(e) => updateNumberOfColumns(fileIndex, e.target.value)}
                          />
                        </Grid>
                      </Grid>

                      {fileError && (
                        <Alert severity="warning" sx={{ mt: 2 }}>
                          {fileError}
                        </Alert>
                      )}

                      <Box sx={{ mt: 3 }}>
                        <Typography variant="h5" sx={{ mb: 2 }}>
                          Column Rules
                        </Typography>

                        <Table size="small">
                          <TableHead>
                            <TableRow>
                              <TableCell>Column</TableCell>
                              <TableCell>Expected Header</TableCell>
                              <TableCell>Numeric</TableCell>
                            </TableRow>
                          </TableHead>
                          <TableBody>
                            {file.columns.map((col, colIndex) => (
                              <TableRow key={`${fileIndex}-${colIndex}`}>
                                <TableCell sx={{ width: 220 }}>
                                  <TextField
                                    fullWidth
                                    size="small"
                                    placeholder="e.g. C"
                                    value={col.column}
                                    onChange={(e) =>
                                      updateColumn(fileIndex, colIndex, "column", e.target.value)
                                    }
                                  />
                                </TableCell>
                                <TableCell>
                                  <TextField
                                    fullWidth
                                    size="small"
                                    placeholder="Expected header text"
                                    value={col.expected_header}
                                    onChange={(e) =>
                                      updateColumn(
                                        fileIndex,
                                        colIndex,
                                        "expected_header",
                                        e.target.value
                                      )
                                    }
                                  />
                                </TableCell>
                                <TableCell sx={{ width: 120 }}>
                                  <Checkbox
                                    checked={col.numeric}
                                    onChange={(e) =>
                                      updateColumn(fileIndex, colIndex, "numeric", e.target.checked)
                                    }
                                  />
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                      </Box>
                    </AccordionDetails>
                  </Accordion>
                );
              })}
            </Stack>
          </CardContent>
        </Card>

        {error && <Alert severity="error">{error}</Alert>}

        {result && (
          <Card>
            <CardContent>
              <Stack spacing={2}>
                <Alert severity={result.success ? "success" : "warning"}>
                  {result.overallStatus} | Files: {result.fileCount} | Passed: {result.passedFiles}
                  {" | "}Failed: {result.failedFiles}
                </Alert>

                {result.files.map((file, fileIndex) => (
                  <Box key={fileIndex}>
                    <Typography variant="h6">
                      {file.fileName} - {file.status}
                    </Typography>

                    {file.errors.map((item, idx) => (
                      <Alert key={idx} severity="error" sx={{ mt: 1 }}>
                        {item}
                      </Alert>
                    ))}

                    <Table size="small" sx={{ mt: 2 }}>
                      <TableHead>
                        <TableRow>
                          <TableCell>Column</TableCell>
                          <TableCell>Expected</TableCell>
                          <TableCell>Actual</TableCell>
                          <TableCell>Header Match</TableCell>
                          <TableCell>Non Blank Count</TableCell>
                          <TableCell>Numeric Sum</TableCell>
                        </TableRow>
                      </TableHead>
                      <TableBody>
                        {file.columns.map((col, idx) => (
                          <TableRow key={idx}>
                            <TableCell>{col.column}</TableCell>
                            <TableCell>{col.expectedHeader}</TableCell>
                            <TableCell>{col.actualHeader}</TableCell>
                            <TableCell>{String(col.headerMatch)}</TableCell>
                            <TableCell>{col.nonBlankCount}</TableCell>
                            <TableCell>{col.numericSum ?? "-"}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </Box>
                ))}
              </Stack>
            </CardContent>
          </Card>
        )}
      </Stack>
    </Container>
  );
}
