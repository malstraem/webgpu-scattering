import * as React from 'react';
import Container from '@mui/material/Container';
import Box from '@mui/material/Box';
import { Switch } from '@mui/material';

export default function App() {
  return (
    <Container maxWidth="sm">
      <Box sx={{ my: 5 }}>
        <canvas></canvas>
        <script type="module" src="./scattering.ts"></script>
        <Switch defaultChecked />
      </Box>
    </Container>
  );
}
