import React, { useState, useEffect } from 'react';
import {
  Container,
  AppBar,
  Toolbar,
  Typography,
  Box,
  Tab,
  Tabs,
  Card,
  CardContent,
  Button,
  Grid,
  Chip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  Switch,
  FormControlLabel,
  Alert,
  LinearProgress,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  IconButton,
  Tooltip
} from '@mui/material';
import {
  Add as AddIcon,
  Delete as DeleteIcon,
  Launch as LaunchIcon,
  Refresh as RefreshIcon,
  Computer as ComputerIcon,
  Storage as StorageIcon,
  Memory as MemoryIcon,
  Speed as SpeedIcon
} from '@mui/icons-material';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';

const theme = createTheme({
  palette: {
    mode: 'dark',
    primary: {
      main: '#1976d2',
    },
    secondary: {
      main: '#dc004e',
    },
  },
});

function TabPanel({ children, value, index, ...other }) {
  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`simple-tabpanel-${index}`}
      aria-labelledby={`simple-tab-${index}`}
      {...other}
    >
      {value === index && (
        <Box sx={{ p: 3 }}>
          {children}
        </Box>
      )}
    </div>
  );
}

function App() {
  const [tabValue, setTabValue] = useState(0);
  const [environments, setEnvironments] = useState([]);
  const [loading, setLoading] = useState(false);
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [metrics, setMetrics] = useState({});
  
  // Form state for creating new environment
  const [newEnv, setNewEnv] = useState({
    name: '',
    base_image: 'ubuntu:22.04',
    custom_image: '',
    cpu: '1',
    memory: '2Gi',
    gpu: '',
    storage: '10Gi',
    cpu_limit: '2',
    memory_limit: '4Gi',
    enable_ssh: true,
    enable_jupyter: false,
    enable_vscode: false,
    team: 'engineering',
    project: '',
    ttl_hours: 24,
    packages: []
  });

  const baseImages = [
    { value: 'ubuntu:20.04', label: 'Ubuntu 20.04 LTS' },
    { value: 'ubuntu:22.04', label: 'Ubuntu 22.04 LTS' },
    { value: 'centos:8', label: 'CentOS 8' },
    { value: 'alpine:latest', label: 'Alpine Linux' },
    { value: 'python:3.11', label: 'Python 3.11' },
    { value: 'jupyter/datascience-notebook', label: 'Jupyter Data Science' },
    { value: 'custom', label: 'Custom Image' }
  ];

  const teams = ['engineering', 'data-science', 'ml-ops', 'research'];

  useEffect(() => {
    fetchEnvironments();
    const interval = setInterval(fetchEnvironments, 30000); // Refresh every 30 seconds
    return () => clearInterval(interval);
  }, []);

  const fetchEnvironments = async () => {
    try {
      setLoading(true);
      const response = await fetch('/api/environments');
      const data = await response.json();
      setEnvironments(data);
      
      // Fetch metrics for each environment
      const metricsPromises = data.map(async (env) => {
        try {
          const metricsResponse = await fetch(`/api/environments/${env.id}/metrics`);
          const metricsData = await metricsResponse.json();
          return { [env.id]: metricsData };
        } catch (error) {
          return { [env.id]: null };
        }
      });
      
      const metricsResults = await Promise.all(metricsPromises);
      const metricsMap = Object.assign({}, ...metricsResults);
      setMetrics(metricsMap);
      
    } catch (error) {
      console.error('Failed to fetch environments:', error);
    } finally {
      setLoading(false);
    }
  };

  const createEnvironment = async () => {
    try {
      setLoading(true);
      
      const payload = {
        name: newEnv.name,
        base_image: newEnv.base_image,
        custom_image: newEnv.base_image === 'custom' ? newEnv.custom_image : null,
        packages: newEnv.packages,
        resources: {
          cpu: newEnv.cpu,
          memory: newEnv.memory,
          gpu: newEnv.gpu || null,
          storage: newEnv.storage
        },
        limits: {
          cpu: newEnv.cpu_limit,
          memory: newEnv.memory_limit,
          gpu: newEnv.gpu || null
        },
        enable_ssh: newEnv.enable_ssh,
        enable_jupyter: newEnv.enable_jupyter,
        enable_vscode: newEnv.enable_vscode,
        team: newEnv.team,
        project: newEnv.project,
        ttl_hours: newEnv.ttl_hours,
        environment_variables: {}
      };

      const response = await fetch('/api/environments', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });

      if (response.ok) {
        setCreateDialogOpen(false);
        fetchEnvironments();
        // Reset form
        setNewEnv({
          name: '',
          base_image: 'ubuntu:22.04',
          custom_image: '',
          cpu: '1',
          memory: '2Gi',
          gpu: '',
          storage: '10Gi',
          cpu_limit: '2',
          memory_limit: '4Gi',
          enable_ssh: true,
          enable_jupyter: false,
          enable_vscode: false,
          team: 'engineering',
          project: '',
          ttl_hours: 24,
          packages: []
        });
      } else {
        throw new Error('Failed to create environment');
      }
    } catch (error) {
      console.error('Failed to create environment:', error);
    } finally {
      setLoading(false);
    }
  };

  const deleteEnvironment = async (envId) => {
    try {
      setLoading(true);
      const response = await fetch(`/api/environments/${envId}`, {
        method: 'DELETE',
      });
      
      if (response.ok) {
        fetchEnvironments();
      } else {
        throw new Error('Failed to delete environment');
      }
    } catch (error) {
      console.error('Failed to delete environment:', error);
    } finally {
      setLoading(false);
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'running': return 'success';
      case 'pending': return 'warning';
      case 'creating': return 'info';
      case 'error': return 'error';
      case 'stopping': return 'warning';
      default: return 'default';
    }
  };

  const formatBytes = (bytes) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <AppBar position="static">
        <Toolbar>
          <ComputerIcon sx={{ mr: 2 }} />
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            DevSecOps Development Platform
          </Typography>
          <Button color="inherit" onClick={fetchEnvironments}>
            <RefreshIcon />
          </Button>
        </Toolbar>
      </AppBar>

      <Container maxWidth="xl" sx={{ mt: 2 }}>
        {loading && <LinearProgress sx={{ mb: 2 }} />}
        
        <Box sx={{ borderBottom: 1, borderColor: 'divider' }}>
          <Tabs value={tabValue} onChange={(e, newValue) => setTabValue(newValue)}>
            <Tab label="Environments" />
            <Tab label="Monitoring" />
            <Tab label="Analytics" />
          </Tabs>
        </Box>

        <TabPanel value={tabValue} index={0}>
          <Box sx={{ mb: 2, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Typography variant="h5">Development Environments</Typography>
            <Button
              variant="contained"
              startIcon={<AddIcon />}
              onClick={() => setCreateDialogOpen(true)}
            >
              Create Environment
            </Button>
          </Box>

          <Grid container spacing={3}>
            {environments.map((env) => (
              <Grid item xs={12} md={6} lg={4} key={env.id}>
                <Card>
                  <CardContent>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 2 }}>
                      <Typography variant="h6" component="div">
                        {env.spec.name}
                      </Typography>
                      <Chip
                        label={env.status}
                        color={getStatusColor(env.status)}
                        size="small"
                      />
                    </Box>
                    
                    <Typography color="text.secondary" gutterBottom>
                      {env.spec.base_image}
                    </Typography>
                    
                    <Box sx={{ mb: 2 }}>
                      <Typography variant="body2">
                        <strong>Team:</strong> {env.spec.team}
                      </Typography>
                      <Typography variant="body2">
                        <strong>Project:</strong> {env.spec.project}
                      </Typography>
                      <Typography variant="body2">
                        <strong>Resources:</strong> {env.spec.resources.cpu} CPU, {env.spec.resources.memory} RAM
                      </Typography>
                      <Typography variant="body2">
                        <strong>Expires:</strong> {new Date(env.expires_at).toLocaleString()}
                      </Typography>
                    </Box>

                    {metrics[env.id] && (
                      <Box sx={{ mb: 2 }}>
                        <Typography variant="body2" color="text.secondary">
                          CPU: {metrics[env.id].cpu_usage_percent.toFixed(1)}% | 
                          Memory: {metrics[env.id].memory_usage_percent.toFixed(1)}% |
                          {metrics[env.id].is_idle ? ' 💤 Idle' : ' 🟢 Active'}
                        </Typography>
                      </Box>
                    )}

                    <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
                      {env.spec.enable_ssh && (
                        <Chip label="SSH" size="small" variant="outlined" />
                      )}
                      {env.spec.enable_jupyter && (
                        <Chip label="Jupyter" size="small" variant="outlined" />
                      )}
                      {env.spec.enable_vscode && (
                        <Chip label="VS Code" size="small" variant="outlined" />
                      )}
                    </Box>

                    <Box sx={{ mt: 2, display: 'flex', justifyContent: 'space-between' }}>
                      <Box>
                        {env.ssh_endpoint && (
                          <Tooltip title={`SSH: ${env.ssh_endpoint}`}>
                            <IconButton size="small">
                              <LaunchIcon />
                            </IconButton>
                          </Tooltip>
                        )}
                      </Box>
                      <IconButton
                        size="small"
                        color="error"
                        onClick={() => deleteEnvironment(env.id)}
                      >
                        <DeleteIcon />
                      </IconButton>
                    </Box>
                  </CardContent>
                </Card>
              </Grid>
            ))}
          </Grid>
        </TabPanel>

        <TabPanel value={tabValue} index={1}>
          <Typography variant="h5" gutterBottom>Resource Monitoring</Typography>
          
          <Grid container spacing={3}>
            <Grid item xs={12} md={3}>
              <Card>
                <CardContent sx={{ textAlign: 'center' }}>
                  <ComputerIcon sx={{ fontSize: 40, mb: 1 }} />
                  <Typography variant="h4">{environments.length}</Typography>
                  <Typography color="text.secondary">Active Environments</Typography>
                </CardContent>
              </Card>
            </Grid>
            
            <Grid item xs={12} md={3}>
              <Card>
                <CardContent sx={{ textAlign: 'center' }}>
                  <SpeedIcon sx={{ fontSize: 40, mb: 1 }} />
                  <Typography variant="h4">
                    {Object.values(metrics).reduce((sum, m) => sum + (m?.cpu_usage_percent || 0), 0).toFixed(1)}%
                  </Typography>
                  <Typography color="text.secondary">Avg CPU Usage</Typography>
                </CardContent>
              </Card>
            </Grid>
            
            <Grid item xs={12} md={3}>
              <Card>
                <CardContent sx={{ textAlign: 'center' }}>
                  <MemoryIcon sx={{ fontSize: 40, mb: 1 }} />
                  <Typography variant="h4">
                    {Object.values(metrics).reduce((sum, m) => sum + (m?.memory_usage_percent || 0), 0).toFixed(1)}%
                  </Typography>
                  <Typography color="text.secondary">Avg Memory Usage</Typography>
                </CardContent>
              </Card>
            </Grid>
            
            <Grid item xs={12} md={3}>
              <Card>
                <CardContent sx={{ textAlign: 'center' }}>
                  <StorageIcon sx={{ fontSize: 40, mb: 1 }} />
                  <Typography variant="h4">
                    {Object.values(metrics).filter(m => m?.is_idle).length}
                  </Typography>
                  <Typography color="text.secondary">Idle Environments</Typography>
                </CardContent>
              </Card>
            </Grid>
          </Grid>

          <Box sx={{ mt: 3 }}>
            <Typography variant="h6" gutterBottom>Environment Details</Typography>
            <TableContainer component={Paper}>
              <Table>
                <TableHead>
                  <TableRow>
                    <TableCell>Environment</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>CPU Usage</TableCell>
                    <TableCell>Memory Usage</TableCell>
                    <TableCell>Network I/O</TableCell>
                    <TableCell>Last Activity</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {environments.map((env) => {
                    const metric = metrics[env.id];
                    return (
                      <TableRow key={env.id}>
                        <TableCell>{env.spec.name}</TableCell>
                        <TableCell>
                          <Chip
                            label={env.status}
                            color={getStatusColor(env.status)}
                            size="small"
                          />
                        </TableCell>
                        <TableCell>
                          {metric ? `${metric.cpu_usage_percent.toFixed(1)}%` : 'N/A'}
                        </TableCell>
                        <TableCell>
                          {metric ? `${metric.memory_usage_percent.toFixed(1)}% (${formatBytes(metric.memory_usage_bytes)})` : 'N/A'}
                        </TableCell>
                        <TableCell>
                          {metric ? `↓${formatBytes(metric.network_rx_bytes)} ↑${formatBytes(metric.network_tx_bytes)}` : 'N/A'}
                        </TableCell>
                        <TableCell>
                          {metric ? new Date(metric.last_activity).toLocaleString() : 'N/A'}
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </TableContainer>
          </Box>
        </TabPanel>

        <TabPanel value={tabValue} index={2}>
          <Typography variant="h5" gutterBottom>Usage Analytics</Typography>
          <Alert severity="info">
            Analytics dashboard showing team usage patterns, cost optimization opportunities, 
            and resource efficiency metrics would be implemented here.
          </Alert>
        </TabPanel>
      </Container>

      {/* Create Environment Dialog */}
      <Dialog open={createDialogOpen} onClose={() => setCreateDialogOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle>Create New Development Environment</DialogTitle>
        <DialogContent>
          <Grid container spacing={2} sx={{ mt: 1 }}>
            <Grid item xs={12} md={6}>
              <TextField
                fullWidth
                label="Environment Name"
                value={newEnv.name}
                onChange={(e) => setNewEnv({ ...newEnv, name: e.target.value })}
              />
            </Grid>
            
            <Grid item xs={12} md={6}>
              <FormControl fullWidth>
                <InputLabel>Base Image</InputLabel>
                <Select
                  value={newEnv.base_image}
                  onChange={(e) => setNewEnv({ ...newEnv, base_image: e.target.value })}
                >
                  {baseImages.map((image) => (
                    <MenuItem key={image.value} value={image.value}>
                      {image.label}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
            </Grid>

            {newEnv.base_image === 'custom' && (
              <Grid item xs={12}>
                <TextField
                  fullWidth
                  label="Custom Image URL"
                  value={newEnv.custom_image}
                  onChange={(e) => setNewEnv({ ...newEnv, custom_image: e.target.value })}
                  placeholder="registry.company.com/my-image:latest"
                />
              </Grid>
            )}

            <Grid item xs={12} md={3}>
              <TextField
                fullWidth
                label="CPU Request"
                value={newEnv.cpu}
                onChange={(e) => setNewEnv({ ...newEnv, cpu: e.target.value })}
                placeholder="1 or 500m"
              />
            </Grid>

            <Grid item xs={12} md={3}>
              <TextField
                fullWidth
                label="Memory Request"
                value={newEnv.memory}
                onChange={(e) => setNewEnv({ ...newEnv, memory: e.target.value })}
                placeholder="2Gi or 512Mi"
              />
            </Grid>

            <Grid item xs={12} md={3}>
              <TextField
                fullWidth
                label="GPU (Optional)"
                value={newEnv.gpu}
                onChange={(e) => setNewEnv({ ...newEnv, gpu: e.target.value })}
                placeholder="1"
              />
            </Grid>

            <Grid item xs={12} md={3}>
              <TextField
                fullWidth
                label="Storage"
                value={newEnv.storage}
                onChange={(e) => setNewEnv({ ...newEnv, storage: e.target.value })}
                placeholder="10Gi"
              />
            </Grid>

            <Grid item xs={12} md={6}>
              <FormControl fullWidth>
                <InputLabel>Team</InputLabel>
                <Select
                  value={newEnv.team}
                  onChange={(e) => setNewEnv({ ...newEnv, team: e.target.value })}
                >
                  {teams.map((team) => (
                    <MenuItem key={team} value={team}>
                      {team}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
            </Grid>

            <Grid item xs={12} md={6}>
              <TextField
                fullWidth
                label="Project"
                value={newEnv.project}
                onChange={(e) => setNewEnv({ ...newEnv, project: e.target.value })}
              />
            </Grid>

            <Grid item xs={12} md={4}>
              <FormControlLabel
                control={
                  <Switch
                    checked={newEnv.enable_ssh}
                    onChange={(e) => setNewEnv({ ...newEnv, enable_ssh: e.target.checked })}
                  />
                }
                label="Enable SSH"
              />
            </Grid>

            <Grid item xs={12} md={4}>
              <FormControlLabel
                control={
                  <Switch
                    checked={newEnv.enable_jupyter}
                    onChange={(e) => setNewEnv({ ...newEnv, enable_jupyter: e.target.checked })}
                  />
                }
                label="Enable Jupyter"
              />
            </Grid>

            <Grid item xs={12} md={4}>
              <FormControlLabel
                control={
                  <Switch
                    checked={newEnv.enable_vscode}
                    onChange={(e) => setNewEnv({ ...newEnv, enable_vscode: e.target.checked })}
                  />
                }
                label="Enable VS Code"
              />
            </Grid>

            <Grid item xs={12}>
              <TextField
                fullWidth
                label="TTL (Hours)"
                type="number"
                value={newEnv.ttl_hours}
                onChange={(e) => setNewEnv({ ...newEnv, ttl_hours: parseInt(e.target.value) })}
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCreateDialogOpen(false)}>Cancel</Button>
          <Button onClick={createEnvironment} variant="contained" disabled={!newEnv.name || loading}>
            Create Environment
          </Button>
        </DialogActions>
      </Dialog>
    </ThemeProvider>
  );
}

export default App;
